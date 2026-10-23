#!/usr/bin/env bash
# Builds target/release/Koil.app.
#
#   scripts/bundle-macos.sh           # bundle linking against the local Qt
#   scripts/bundle-macos.sh --deploy  # also copy Qt into the bundle (macdeployqt)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/target/release/Koil.app"
# Without this, cc and rustc target the build machine's macOS version, so the
# app wouldn't launch on anything older. Keep in sync with Info.plist.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"
version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/Cargo.toml" | head -1)"

# --locked: what Cargo.lock has (koil-core's commit too), or fail.
cargo build --release --locked --manifest-path "$root/Cargo.toml"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/target/release/koil" "$app/Contents/MacOS/Koil"
sed "s/@VERSION@/$version/g" "$root/packaging/macos/Info.plist" > "$app/Contents/Info.plist"
cp "$root/packaging/macos/Koil.icns" "$app/Contents/Resources/"

if [[ "${1:-}" == "--deploy" ]]; then
    macdeployqt "$app" -qmldir="$root/qml"
    # What macdeployqt copies that Koil never loads (run with
    # DYLD_PRINT_LIBRARIES=1, it loads none of it), a quarter of the .dmg:
    # the Controls styles but macOS's and the Fusion and Basic it falls back
    # to, QML modules nothing imports, and plugins for what Koil doesn't do:
    # pictures (image formats, SVG icons), the network (TLS), widgets (their
    # style: it has no QApplication) and databases (whose drivers' client
    # libraries macdeployqt can't find: its "ERROR: no file at" lines).
    contents="$app/Contents"
    for style in FluentWinUI3 iOS Imagine Material Universal; do
        rm -rf "$contents/Resources/qml/QtQuick/Controls/$style"
        lower="$(tr '[:upper:]' '[:lower:]' <<< "$style")"
        rm -f "$contents/PlugIns/quick/libqtquickcontrols2${lower}style"{,impl}plugin.dylib
        rm -rf "$contents/Frameworks/QtQuickControls2$style.framework"
    done
    rm -rf "$contents/Frameworks/QtQuickControls2IOSStyleImpl.framework" \
        "$contents/Frameworks/QtQuickControls2"{FluentWinUI3,Imagine,Material,Universal}StyleImpl.framework
    for module in QtQuick/Particles QtQuick/VectorImage QtQuick/Shapes/DesignHelpers \
        QtQuick/LocalStorage QtQml/XmlListModel QtQuick/tooling; do
        rm -rf "$contents/Resources/qml/$module"
    done
    rm -f "$contents/PlugIns/quick/"lib{particles,qquickvectorimage,qquickvectorimagehelpers}plugin.dylib \
        "$contents/PlugIns/quick/"lib{qtquickshapesdesignhelpers,qmllocalstorage,qmlxmllistmodel,quicktooling}plugin.dylib
    rm -rf "$contents/Frameworks/Qt"{QuickParticles,QuickVectorImage,QuickVectorImageHelpers}.framework \
        "$contents/Frameworks/Qt"{QuickVectorImageGenerator,QuickShapesDesignHelpers}.framework \
        "$contents/Frameworks/Qt"{QmlLocalStorage,Sql,QmlXmlListModel,Svg}.framework
    rm -rf "$contents/PlugIns/"{imageformats,iconengines,tls,networkinformation,styles,sqldrivers}
    # macdeployqt rewrites library paths, which breaks the linker's ad-hoc
    # signature; Apple Silicon refuses to run unsigned code, so re-sign.
    codesign --force --deep --sign - "$app"
fi

echo "Built $app"
