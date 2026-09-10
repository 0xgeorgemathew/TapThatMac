#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${TEAM_ID:?Set TEAM_ID}"
: "${NOTARY_PROFILE:?Set a notarytool keychain profile}"
[[ "$SIGNING_IDENTITY" == 'Developer ID Application:'* ]] || { echo 'Developer ID Application signing is required.' >&2; exit 1; }
bash scripts/build-app.sh
app="dist/TapThatX.app"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --identifier com.tapthatx.sensor.helper "$app/Contents/MacOS/TapSensorHelper"
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" dist/TapThatX-notarization.zip
xcrun notarytool submit dist/TapThatX-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --keepParent "$app" dist/TapThatX.zip
echo 'Notarized artifact prepared. Second-Mac installation verification remains required.'
