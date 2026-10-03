#!/usr/bin/env bash
# Makes the app's icons from packaging/icon.png (run it after changing that;
# its output is committed, so building doesn't need ImageMagick):
#   packaging/macos/Koil.icns    the bundle's icon
#   packaging/windows/koil.ico   the exe's icon (koil.rc) and the installer's
#   packaging/window-icon.png    the window's, where neither is used (Linux,
#                                and `cargo run` on macOS)
# Needs ImageMagick (`magick`) and macOS's `iconutil`.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/packaging/icon.png"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# macOS draws icons as they are, so the rounded square must be the size of
# other apps': 824 of 1024 pixels (Apple's grid). It's 1128 of icon.png's
# 1254, so the whole image goes to 1254 * 824 / 1128 = 916 of 1024.
magick "$src" -resize 916x916 -background none -gravity center -extent 1024x1024 \
    "$work/mac.png"

iconset="$work/Koil.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    magick "$work/mac.png" -resize "${size}x${size}" "$iconset/icon_${size}x${size}.png"
    magick "$work/mac.png" -resize "$((size * 2))x$((size * 2))" \
        "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$root/packaging/macos/Koil.icns"

magick "$work/mac.png" -resize 512x512 "$root/packaging/window-icon.png"

# Windows icons fill their square.
magick "$src" -define icon:auto-resize=256,64,48,40,32,24,20,16 \
    "$root/packaging/windows/koil.ico"
