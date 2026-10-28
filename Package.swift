// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioProbe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AudioProbe", targets: ["AudioProbe"])],
    targets: [
        .target(name: "Gain"),
        .executableTarget(name: "AudioProbe", dependencies: ["Gain"])
    ]
)
