#!/bin/bash
# Rasterize the app icon SVG into the macOS app icon set.
# Uses Quick Look, which ships with macOS. ImageMagick's own SVG renderer drops the strokes.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
svg="$root/NB Timer/Icon/AppIcon.svg"
out="$root/NB Timer/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$svg" ]]; then
  echo "Missing $svg" >&2
  exit 1
fi

render() {
  local pixels="$1"
  local filename="$2"
  local tmp rendered
  tmp="$(mktemp -d)"
  qlmanage -t -s "$pixels" -o "$tmp" "$svg" >/dev/null
  rendered="$(find "$tmp" -name '*.png' -print -quit)"
  sips -z "$pixels" "$pixels" "$rendered" --out "${out}/${filename}" >/dev/null
  rm -rf "$tmp"
}

render 16   "icon_16x16.png"
render 32   "icon_32x32 1.png"
render 32   "icon_32x32.png"
render 64   "icon_32x32@2x.png"
render 128  "icon_128x128.png"
render 256  "icon_256x256 1.png"
render 256  "icon_256x256.png"
render 512  "icon_512x512 1.png"
render 512  "icon_512x512.png"
render 1024 "icon_512x512@2x.png"

echo "Wrote app icons to ${out}"
