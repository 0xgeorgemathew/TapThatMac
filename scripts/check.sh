#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
swift build -c release
for script in scripts/*.sh; do
  bash -n "$script"
done
plutil -lint Packaging/Info.plist Packaging/com.tapthatmac.sensor.plist
