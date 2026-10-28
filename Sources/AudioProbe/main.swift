import AppKit
import SwiftUI
import CoreAudio
import Gain

struct ProbeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else { throw ProbeFailure(message: "\(operation): OSStatus \(status)") }
}
func address(_ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T) throws -> T {
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    var a = address(selector)
    try check(AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value), "Read \(selector)")
    return value
}
func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
    var a = address(selector)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size), "List size")
    guard size > 0 else { return [] }
    var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try result.withUnsafeMutableBytes {
        try check(AudioObjectGetPropertyData(object, &a, 0, nil, &size, $0.baseAddress!), "List processes")
    }
    return result
}

struct AudioProcess: Identifiable {
    let id: AudioObjectID
    let pid: pid_t
    let name: String
}

@available(macOS 14.2, *)
final class Route {
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?

    init(process: AudioObjectID) throws {
        do {
            let output = try scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
            guard output != 0 else { throw ProbeFailure(message: "No default audio output") }
            let uid = try scalar(output, kAudioDevicePropertyDeviceUID, Optional<CFString>.none)
            guard let uid else { throw ProbeFailure(message: "Output has no UID") }
            // This spike deliberately supports output-only devices. Reject ambiguous
            // input layouts instead of copying a microphone buffer into the output.
            var inputAddress = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
            var inputSize: UInt32 = 0
            try check(AudioObjectGetPropertyDataSize(output, &inputAddress, 0, nil, &inputSize), "Read output inputs")
            let storage = UnsafeMutableRawPointer.allocate(byteCount: max(Int(inputSize), MemoryLayout<AudioBufferList>.size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            try check(AudioObjectGetPropertyData(output, &inputAddress, 0, nil, &inputSize, storage), "Read input layout")
            let inputs = storage.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers
            guard inputs == 0 else { throw ProbeFailure(message: "Spike: choose built-in speakers or another output-only device before testing.") }

            let description = CATapDescription(stereoMixdownOfProcesses: [process])
            description.name = "AudioProbe temporary tap"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(description, &tap), "Create process tap")
            var format = try scalar(tap, kAudioTapPropertyFormat, AudioStreamBasicDescription())
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32 else {
                throw ProbeFailure(message: "Spike requires Float32 PCM")
            }
            format.mReserved = 0
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "AudioProbe temporary output",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "Create aggregate")
            try check(AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
                let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                let destination = UnsafeMutableAudioBufferListPointer(output)
                for buffer in destination {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                // Fail silent on an unsupported buffer layout, never reinterpret it.
                guard source.count == destination.count else { return }
                for index in destination.indices {
                    let src = source[index]
                    let dst = destination[index]
                    guard src.mNumberChannels == dst.mNumberChannels,
                          src.mDataByteSize == dst.mDataByteSize,
                          let from = src.mData, let to = dst.mData else { continue }
                    probe_copy_gain(from.assumingMemoryBound(to: Float.self), to.assumingMemoryBound(to: Float.self), Int(dst.mDataByteSize) / MemoryLayout<Float>.size)
                }
            }, "Create audio callback")
            try check(AudioDeviceStart(aggregate, proc), "Start audio")
        } catch {
            stop()
            throw error
        }
    }
    func stop() {
        if let proc {
            AudioDeviceStop(aggregate, proc)
            AudioDeviceDestroyIOProcID(aggregate, proc)
        }
        proc = nil
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }
}

@available(macOS 14.2, *)
@MainActor final class Model: ObservableObject {
    @Published var processes: [AudioProcess] = []
    @Published var selected: AudioObjectID = 0
    @Published var volume: Double = 1 { didSet { probe_set_gain(Float(volume)) } }
    @Published var status = "Play audio, then refresh. Select one process for the test."
    @Published var running = false
    private var route: Route?
    func refresh() {
        do {
            processes = try objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).compactMap { id in
                let active = try scalar(id, kAudioProcessPropertyIsRunningOutput, UInt32(0))
                let pid = try scalar(id, kAudioProcessPropertyPID, pid_t(0))
                guard active != 0, pid != getpid() else { return nil }
                let app = NSRunningApplication(processIdentifier: pid)
                return AudioProcess(id: id, pid: pid, name: app?.localizedName ?? "Audio process")
            }.sorted { $0.name < $1.name }
            if !processes.contains(where: { $0.id == selected }) { selected = processes.first?.id ?? 0 }
        } catch { status = error.localizedDescription }
    }
    func start() {
        stop()
        guard selected != 0 else { status = "Select a playing process first."; return }
        do {
            probe_set_gain(Float(volume))
            route = try Route(process: selected)
            running = true
            status = "Route started. Verify sound manually; silence is not proof of success. Stop restores the original path."
        } catch { status = error.localizedDescription }
    }
    func stop() {
        route?.stop()
        route = nil
        running = false
        status = "Stopped. Original audio path restored."
    }
}

@available(macOS 14.2, *)
struct Panel: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Audio Probe · experimental").font(.headline)
            Picker("Audio process", selection: $model.selected) {
                Text("Select").tag(AudioObjectID(0))
                ForEach(model.processes) { process in
                    Text("\(process.name) · PID \(process.pid)").tag(process.id)
                }
            }.disabled(model.running)
            HStack {
                Slider(value: $model.volume, in: 0...1)
                Text("\(Int(model.volume * 100))% ").monospacedDigit().frame(width: 48)
            }
            HStack {
                Button("Refresh", action: model.refresh).disabled(model.running)
                Button("Start test", action: model.start).disabled(model.running || model.selected == 0)
                Button("Stop / restore", action: model.stop)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Quit") { model.stop(); NSApplication.shared.terminate(nil) }
        }.padding(18).frame(width: 390).onAppear { model.refresh() }
    }
}

@available(macOS 14.2, *)
struct ProbeApp: App {
    @StateObject private var model = Model()
    var body: some Scene {
        MenuBarExtra("Audio Probe", systemImage: "speaker.wave.2") { Panel(model: model) }
            .menuBarExtraStyle(.window)
    }
}
if #available(macOS 14.2, *) {
    ProbeApp.main()
} else {
    fputs("Requires macOS 14.2 or later.\n", stderr)
}
