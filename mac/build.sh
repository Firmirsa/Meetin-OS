#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-$PWD/.build/Meetin-OS.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
icon_work=$(mktemp -d)
trap 'rm -rf "$icon_work"' EXIT
mkdir "$icon_work/MeetinOS.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" ../brand/logo/app-icon-1024.png \
    --out "$icon_work/MeetinOS.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" ../brand/logo/app-icon-1024.png \
    --out "$icon_work/MeetinOS.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work/MeetinOS.iconset" -o "$app/Contents/Resources/MeetinOS.icns"
cp ../brand/logo/app-icon-1024.png "$app/Contents/Resources/MeetinOS.png"
cp Info.plist "$app/Contents/Info.plist"
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" MeetinOS.swift Capture.swift Gladia.swift ZoomMeetingDetector.swift ../brand/MeetinTheme.swift -o "$app/Contents/MacOS/MeetinOS"
codesign --force --sign - "$app"
