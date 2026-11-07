#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-$PWD/.build/Meetin-OS.app}"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" MeetinOS.swift Capture.swift Gladia.swift ZoomMeetingDetector.swift -o "$app/Contents/MacOS/MeetinOS"
codesign --force --sign - "$app"
