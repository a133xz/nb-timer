#!/bin/bash
# Redraw the icon, build NB Timer, and replace the copy in ~/Applications.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/make-app-icon.sh"

derived="/tmp/NBTimerBuild"
xcodebuild \
  -project "NB Timer.xcodeproj" \
  -scheme "NB Timer" \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  build

app="$derived/Build/Products/Release/NB Timer.app"
identity="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
  identity="-"
fi

codesign --force --deep --sign "$identity" --entitlements "NB Timer/NB Timer.entitlements" "$app"

osascript -e 'quit app "NB Timer"' || true
# `open` fails with -600 if the old instance is still shutting down.
for _ in {1..50}; do
  pgrep -xq "NB Timer" || break
  sleep 0.1
done
pkill -x "NB Timer" || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/NB Timer.app"
cp -R "$app" "$HOME/Applications/NB Timer.app"
open "$HOME/Applications/NB Timer.app"

echo "Installed $HOME/Applications/NB Timer.app"
