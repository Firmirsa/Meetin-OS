#!/bin/bash
set -euo pipefail

mac_dir=$(cd "$(dirname "$0")" && pwd)
app_identity=""
if [[ "${1:-}" == --beta ]]; then
  shift
else
  app_identity="${MEETIN_APP_SIGN_IDENTITY:?Certificat Developer ID Application requis. Utilise --beta pour un paquet de test.}"
  : "${MEETIN_INSTALLER_SIGN_IDENTITY:?Certificat Developer ID Installer requis.}"
  : "${MEETIN_NOTARY_PROFILE:?Profil de trousseau notarytool requis.}"
fi
output="${1:-$mac_dir/.build/Meetin-OS.pkg}"
if [[ $# -gt 1 || "$output" != *.pkg || -d "$output" ]]; then
  printf 'Usage: %s [--beta] [chemin/Meetin-OS.pkg]\n' "$0" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
payload="$work/payload"
app="$payload/Meetin-OS.app"
MEETIN_APP_SIGN_IDENTITY="$app_identity" "$mac_dir/build.sh" "$app" --universal
codesign --verify --strict --all-architectures "$app"

components="$work/components.plist"
pkgbuild --analyze --root "$payload" "$components"
# Une copie déplacée ou issue d'un ancien build ne doit pas changer la destination.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$components"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
component="$work/Meetin-OS-app.pkg"
pkgbuild --root "$payload" --component-plist "$components" \
  --install-location /Applications --identifier com.meetin-os.installer \
  --version "$version" "$component"

minimum_macos=$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")
requirements="$work/requirements.plist"
plutil -create xml1 "$requirements"
plutil -insert os -json "[\"$minimum_macos\"]" "$requirements"
plutil -insert hostArchitectures -json '["arm64","x86_64"]' "$requirements"

package="$work/Meetin-OS.pkg"
product_args=(--product "$requirements" --package "$component")
if [[ -n "$app_identity" ]]; then
  product_args+=(--sign "$MEETIN_INSTALLER_SIGN_IDENTITY" --timestamp)
fi
productbuild "${product_args[@]}" "$package"

if [[ -n "$app_identity" ]]; then
  xcrun notarytool submit "$package" --keychain-profile "$MEETIN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$package"
  xcrun stapler validate "$package"
fi

mkdir -p "$(dirname "$output")"
mv "$package" "$output"
printf 'Installateur prêt : %s\n' "$output"
