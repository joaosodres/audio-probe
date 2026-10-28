#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Build requires macOS 14.2+ and Xcode Command Line Tools.' >&2
    exit 1
fi
swift build -c release
app="$PWD/build/AudioProbe.app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/AudioProbe "$app/Contents/MacOS/AudioProbe"
cp Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "Built $app"
echo 'Run: open build/AudioProbe.app'
