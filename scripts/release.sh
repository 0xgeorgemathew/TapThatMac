#!/bin/bash
# Packages a signed release for GitHub: the zip install.sh downloads, its checksum, and a DMG.
#
#   bash scripts/release.sh 0.1.0-beta.1
#
# Builds with the identity in scripts/signing.env, leaves /Applications alone, and writes
# dist/release/TapThatMac-<version>.{zip,zip.sha256,dmg}. Publish with the printed gh command.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?Usage: bash scripts/release.sh <version, e.g. 0.1.0-beta.1>}"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
[[ "$version" == "$bundle_version" || "$version" == "$bundle_version"-* ]] || {
  echo "Version $version doesn't match CFBundleShortVersionString $bundle_version in Packaging/Info.plist." >&2
  exit 1
}

SKIP_APP_INSTALL=1 bash scripts/build-app.sh
app="dist/Tap That Mac.app"
identity="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[[ -n "$identity" ]] || { echo 'Refusing to release an ad-hoc build: the sensor helper needs a signed app.' >&2; exit 1; }

out="dist/release"
rm -rf "$out" && mkdir -p "$out"
zip="$out/TapThatMac-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
(cd "$out" && shasum -a 256 "$(basename "$zip")" > "$(basename "$zip").sha256")

bash scripts/create-dmg.sh
mv dist/tapthatmac.dmg "$out/TapThatMac-$version.dmg"

echo
echo "Signed by: $identity"
cat "$zip.sha256"
echo
echo "Publish:"
echo "  gh release create v$version $out/* --prerelease --title 'Tap That Mac $version' --notes-file <notes.md>"
