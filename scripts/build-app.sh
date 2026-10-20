#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing-config.sh
load_signing_config scripts/signing.env
swift build -c release --arch arm64
bin_dir="$(swift build -c release --arch arm64 --show-bin-path)"
mkdir -p dist
build_stage="$(mktemp -d dist/.tapthatmac-build.XXXXXX)"
trap 'rm -rf "$build_stage"' EXIT
app="$build_stage/Tap That Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchDaemons" "$app/Contents/Resources"
cp "$bin_dir/TapThatMac" "$app/Contents/MacOS/TapThatMac"
cp "$bin_dir/TapSensorHelper" "$app/Contents/MacOS/TapSensorHelper"
cp docs/SENSOR_REFERENCE_LICENSE.txt "$app/Contents/Resources/"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp Packaging/com.tapthatmac.sensor.plist "$app/Contents/Library/LaunchDaemons/"
if [[ -f Packaging/AppIcon.icns ]]; then
  cp Packaging/AppIcon.icns "$app/Contents/Resources/"
fi
if [[ -d Packaging/Assets ]]; then
  cp Packaging/Assets/AppIcon*.png "$app/Contents/Resources/" 2>/dev/null || true
fi
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" != "-" ]]; then
  : "${TEAM_ID:?Set TEAM_ID to the signing certificate team identifier}"
  [[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid TEAM_ID' >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Add :TapThatMacTeamIdentifier string $TEAM_ID" "$app/Contents/Info.plist"
fi
codesign --force --options runtime --timestamp=none --sign "$identity" --identifier com.tapthatmac.sensor.helper "$app/Contents/MacOS/TapSensorHelper"
if [[ "$identity" != "-" ]]; then
  actual_team="$(codesign -dv "$app/Contents/MacOS/TapSensorHelper" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  if [[ "$actual_team" != "$TEAM_ID" ]]; then
    echo "TEAM_ID must match the certificate team: $actual_team" >&2
    exit 1
  fi
fi
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
# A local development build need not pass distribution assessment. Revocation
# and other certificate errors are different from an ordinary "rejected" result.
assessment="$build_stage/gatekeeper.txt"
assessment_status=0
spctl --assess --type execute --verbose=4 "$app" >"$assessment" 2>&1 || assessment_status=$?
if [[ "$assessment_status" != "0" ]]; then
  if [[ "$assessment_status" != "3" ]] || grep -Eiq 'CSSMERR|errSec|revoked|invalid signature' "$assessment"; then
    cat "$assessment" >&2
    echo 'Signing assessment error; refusing to publish this bundle.' >&2
    exit 1
  fi
  echo 'Local development build. Distribution assessment was rejected; this does not establish whether a locally built app can launch.' >&2
fi
# Publish only after integrity and signing trust checks, preserving the previous build on failure.
if [[ -d "dist/Tap That Mac.app" ]]; then
  mv "dist/Tap That Mac.app" "$build_stage/previous.app"
fi
if ! mv "$app" "dist/Tap That Mac.app"; then
  if [[ -d "$build_stage/previous.app" ]]; then mv "$build_stage/previous.app" "dist/Tap That Mac.app"; fi
  exit 1
fi
echo "Built dist/Tap That Mac.app (identity: $identity). Developer ID distribution requires scripts/notarize.sh."
# Install over the app in /Applications so permission grants tied to the
# signature and install path stay valid. ditto preserves the metadata cp may not.
if [[ -n "${SKIP_APP_INSTALL:-}" && "${SKIP_APP_INSTALL}" != "0" ]]; then
  echo 'Skipping /Applications install (SKIP_APP_INSTALL is set).'
else
  osascript -e 'tell application "Tap That Mac" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x TapThatMac >/dev/null || break
    sleep 0.1
  done
  pkill -x TapThatMac || true
  rm -rf "/Applications/Tap That Mac.app"
  ditto "dist/Tap That Mac.app" "/Applications/Tap That Mac.app"
  if ! cmp -s "dist/Tap That Mac.app/Contents/MacOS/TapThatMac" "/Applications/Tap That Mac.app/Contents/MacOS/TapThatMac"; then
    echo 'Installed app binary differs from "dist/Tap That Mac.app"; install did not complete.' >&2
    exit 1
  fi
  echo "Replaced /Applications/Tap That Mac.app (identity: $identity)."
  # Relaunch the regular app and show its main window.
  open "/Applications/Tap That Mac.app"
fi
