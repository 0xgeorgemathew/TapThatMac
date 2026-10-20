#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d "dist/Tap That Mac.app" ]]; then
  echo "Building dist/Tap That Mac.app first..."
  bash scripts/build-app.sh
fi

dmg_temp_dir="$(mktemp -d dist/.dmg-stage.XXXXXX)"
trap 'rm -rf "$dmg_temp_dir"' EXIT

dmg_mount_point="$(mktemp -d dist/.dmg-mount.XXXXXX)"
trap 'rm -rf "$dmg_temp_dir" "$dmg_mount_point"' EXIT

dmg_name="Tap That Mac"
dmg_final="dist/tapthatmac.dmg"
dmg_sparse="$dmg_temp_dir/temp.sparseimage"

echo "Staging DMG contents..."
stage="$dmg_temp_dir/stage"
mkdir -p "$stage/.background"
cp -R "dist/Tap That Mac.app" "$stage/Tap That Mac.app"
ln -s /Applications "$stage/Applications"
cp "Packaging/Start Here.txt" "$stage/Start Here.txt"

if [[ -f Packaging/dmg/dmg_background.png ]]; then
  cp Packaging/dmg/dmg_background.png "$stage/.background/background.png"
fi

if [[ -f Packaging/dmg/VolumeIcon.icns ]]; then
  cp Packaging/dmg/VolumeIcon.icns "$stage/.VolumeIcon.icns"
fi

echo "Creating disk image..."
rm -f "$dmg_final"

hdiutil create -size 200m -fs HFS+ -volname "$dmg_name" "$dmg_sparse" >/dev/null
hdiutil attach "$dmg_sparse" -mountpoint "$dmg_mount_point" -nobrowse -quiet

cp -R "$stage/"* "$dmg_mount_point/" 2>/dev/null || true
cp -R "$stage/."* "$dmg_mount_point/" 2>/dev/null || true

# Set custom volume icon flag if SetFile is available
if command -v SetFile >/dev/null 2>&1 && [[ -f "$dmg_mount_point/.VolumeIcon.icns" ]]; then
  SetFile -a C "$dmg_mount_point" 2>/dev/null || true
fi

# AppleScript to position icons and set background if UI session available
osascript <<APPLESCRIPT 2>/dev/null || true
tell application "Finder"
  tell disk "$dmg_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 200, 1060, 600}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    if exists file ".background:background.png" then
      set background picture of viewOptions to file ".background:background.png"
    end if
    set position of item "Tap That Mac.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    set position of item "Start Here.txt" of container window to {330, 310}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$dmg_mount_point" -quiet

echo "Converting to compressed DMG..."
hdiutil convert "$dmg_sparse" -format UDZO -imagekey zlib-level=9 -o "$dmg_final" >/dev/null
rm -rf "$dmg_temp_dir" "$dmg_mount_point"
trap - EXIT

echo "Created $dmg_final successfully."
