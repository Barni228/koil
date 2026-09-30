#!/usr/bin/env bash
# Builds a self-contained Koil.app and wraps it in a drag-to-Applications
# disk image: dist/Koil-<version>-macos-<arch>.dmg
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/Cargo.toml" | head -1)"
dmg="$root/dist/Koil-$version-macos-$(uname -m).dmg"

"$root/scripts/bundle-macos.sh" --deploy

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$root/target/release/Koil.app" "$staging/"
ln -s /Applications "$staging/Applications"

mkdir -p "$root/dist"
rm -f "$dmg"
hdiutil create -volname Koil -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"

echo "Built $dmg"
