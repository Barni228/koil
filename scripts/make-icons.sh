#!/usr/bin/env bash
# Makes the app's icons from packaging/icon.png (run it after changing that;
# its output is committed, so building doesn't need ImageMagick). icon.png
# is the macOS icon as it's drawn: 1024 pixels, with Apple's rounded square
# (824 of them) in the middle (see App icon in CLAUDE.md).
# Needs ImageMagick (`magick`) and macOS's `iconutil`.
set -euo pipefail

cd "$(dirname "$0")/../packaging"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir "$work/Koil.iconset"
for size in 16 32 128 256 512; do
    magick icon.png -resize "${size}x${size}" "$work/Koil.iconset/icon_${size}x${size}.png"
    magick icon.png -resize "$((size * 2))x$((size * 2))" \
        "$work/Koil.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$work/Koil.iconset" -o macos/Koil.icns

magick icon.png -resize 512x512 window-icon.png

# Windows icons nearly fill their square: it's 90% of them.
magick icon.png -gravity center -crop 916x916+0+0 +repage \
    -define icon:auto-resize=256,64,48,40,32,24,20,16 windows/koil.ico
