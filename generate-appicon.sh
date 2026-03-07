#!/bin/bash
set -e

# generate-appicon.sh - Generates AppIcon.appiconset from icon_source.svg
# Requires: icon_source.svg in repo root. Uses macOS built-in qlmanage and sips.
#
# Run from repo root: ./generate-appicon.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && pwd)"
SOURCE_SVG="$REPO_ROOT/icon_source.svg"
ICONSET="$REPO_ROOT/NextcloudDeck/Assets.xcassets/AppIcon.appiconset"

echo "Output: $ICONSET"
mkdir -p "$ICONSET"

# Obtain 1024x1024 source PNG: use existing, or convert from SVG via rsvg-convert or qlmanage
TEMP_PNG=""
if [ -f "$ICONSET/icon_1024.png" ]; then
  TEMP_PNG="$ICONSET/icon_1024.png"
  echo "Using existing icon_1024.png"
elif command -v rsvg-convert &>/dev/null && [ -f "$SOURCE_SVG" ]; then
  TEMP_PNG=$(mktemp).png
  rsvg-convert -w 1024 -h 1024 "$SOURCE_SVG" -o "$TEMP_PNG"
  echo "Converted SVG with rsvg-convert"
elif [ -f "$SOURCE_SVG" ]; then
  QLDIR=$(mktemp -d)
  trap "rm -rf '$QLDIR'" EXIT
  qlmanage -t -s 1024 -o "$QLDIR" "$SOURCE_SVG" 2>/dev/null || true
  for f in "$QLDIR"/*.png; do
    [ -f "$f" ] && TEMP_PNG="$f" && break
  done
  [ -n "$TEMP_PNG" ] && echo "Converted SVG with qlmanage"
fi

if [ -z "$TEMP_PNG" ] || [ ! -f "$TEMP_PNG" ]; then
  echo "Error: No 1024x1024 PNG source. Either:"
  echo "  - Add NextcloudDeck/Assets.xcassets/AppIcon.appiconset/icon_1024.png, or"
  echo "  - Install librsvg: brew install librsvg (for rsvg-convert), or"
  echo "  - Ensure icon_source.svg exists and qlmanage can convert it."
  exit 1
fi

# Ensure we have 1024x1024 for resizing
if ! sips -g pixelWidth -g pixelHeight "$TEMP_PNG" 2>/dev/null | grep -q 1024; then
  sips -z 1024 1024 "$TEMP_PNG" --out "$TEMP_PNG"
fi

mkdir -p "$ICONSET"

# macOS App Icon sizes (pt x scale = px): 16@1x, 16@2x, 32@1x, 32@2x, 128@1x, 128@2x, 256@1x, 256@2x, 512@1x, 512@2x
declare -a SIZES=(16 32 128 256 512)
for SIZE in "${SIZES[@]}"; do
  sips -z $SIZE $SIZE "$TEMP_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}.png"
  S2=$((SIZE * 2))
  sips -z $S2 $S2 "$TEMP_PNG" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png"
done

# Update Contents.json with filenames
cat > "$ICONSET/Contents.json" << 'CONTENTS'
{
  "images" : [
    { "filename" : "icon_16x16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",   "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",   "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",   "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
CONTENTS

echo "✅ App icon set generated in $ICONSET"
