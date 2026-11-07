#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="${1:-$PWD/.build/Meetin-OS.app}"
minimum_macos=$(plutil -extract LSMinimumSystemVersion raw Info.plist)
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/MeetinOS.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" ../brand/logo/app-icon-1024.png \
    --out "$work/MeetinOS.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" ../brand/logo/app-icon-1024.png \
    --out "$work/MeetinOS.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$work/MeetinOS.iconset" -o "$app/Contents/Resources/MeetinOS.icns"
cp ../brand/logo/app-icon-1024.png "$app/Contents/Resources/MeetinOS.png"
cp ../brand/logo/google-g.png "$app/Contents/Resources/GoogleG.png"
mkdir -p "$app/Contents/Resources/Fonts"
cp ../brand/fonts/*.ttf ../brand/fonts/OFL-*.txt "$app/Contents/Resources/Fonts/"
cp Info.plist "$app/Contents/Info.plist"
if [[ -n "${MEETIN_WEB_URL:-}" ]]; then
  plutil -insert MeetinWebURL -string "$MEETIN_WEB_URL" "$app/Contents/Info.plist"
fi

compile() {
  swiftc -parse-as-library -target "$1-apple-macos$minimum_macos" \
    MeetinOS.swift Capture.swift Gladia.swift AgentClient.swift AgentExecutionView.swift AgentWorkspace.swift Integrations.swift MeetingDetector.swift MeetingAccessibility.swift MainWindow.swift Sidebar.swift HomeView.swift MeetingsView.swift SettingsPages.swift MeetingStore.swift MeetingFlow.swift MeetinSite.swift NightTheme.swift HostedAccount.swift HostedAccountView.swift GoogleSignIn.swift WelcomeView.swift LiveTranscription.swift LiveTranscriptPanel.swift LiveAlerts.swift TaskDetection.swift ProposalCards.swift TaskActions.swift TaskNotifications.swift \
    ../brand/MeetinTheme.swift ../brand/MeetinComponents.swift -o "$2"
}

executable="$app/Contents/MacOS/MeetinOS"
if [[ "${2:-}" == --universal ]]; then
  compile arm64 "$work/MeetinOS-arm64"
  compile x86_64 "$work/MeetinOS-x86_64"
  lipo -create "$work/MeetinOS-arm64" "$work/MeetinOS-x86_64" -output "$executable"
else
  compile "$(uname -m)" "$executable"
fi

if [[ -n "${MEETIN_APP_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --entitlements Entitlements.plist \
    --sign "$MEETIN_APP_SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app"
fi
