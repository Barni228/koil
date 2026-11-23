#!/bin/sh
# Builds Koil for the web (Qt for WebAssembly) into target/web/: the page,
# its script and wasm, and Qt's loader, ready to serve as they are. See
# docs/platform.md, Web, for why it goes this way.
#
# It takes, from the environment:
#   QT_WASM  Qt for WebAssembly, single-threaded (aqt's `all_os wasm
#            <version> wasm_singlethread`), required.
#   QT_HOST  the desktop Qt of the same version, whose tools build for it
#            (default: the one whose qmake is on PATH).
#   EMSDK    the Emscripten SDK, at the version that Qt asks for (default:
#            the emcc on PATH).
# Uses the local koil-core if .cargo/config.toml patches it in (see
# CLAUDE.md), as cargo build does.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
build=$root/target/web-build
out=$root/target/web

fail() {
    echo "build-web.sh: $*" >&2
    exit 1
}

[ -n "${QT_WASM:-}" ] || fail "set QT_WASM to Qt for WebAssembly, as aqt installs it:
  uvx --from aqtinstall aqt install-qt all_os wasm 6.11.2 wasm_singlethread -O <dir>
  then QT_WASM=<dir>/6.11.2/wasm_singlethread"
[ -f "$QT_WASM/bin/qt-cmake" ] || fail "QT_WASM ($QT_WASM) has no bin/qt-cmake"
QT_WASM=$(cd "$QT_WASM" && pwd)

qmake=${QT_HOST:+$QT_HOST/bin/}qmake
command -v "$qmake" >/dev/null || fail "no $qmake: set QT_HOST to a desktop Qt"
query() { "$qmake" -query "$1"; }
version=$(sed -n 's/^QT_VERSION = //p' "$QT_WASM/mkspecs/qconfig.pri")
[ "$(query QT_VERSION)" = "$version" ] ||
    fail "the desktop Qt is $(query QT_VERSION), but QT_WASM is $version: they must be the same"

if [ -n "${EMSDK:-}" ]; then
    # shellcheck disable=SC1091
    . "$EMSDK/emsdk_env.sh" >/dev/null 2>&1
fi
command -v emcc >/dev/null || fail "no emcc: set EMSDK to the Emscripten SDK"
wanted=$(sed -n 's/.*set(QT_EMCC_RECOMMENDED_VERSION "\(.*\)").*/\1/p' \
    "$QT_WASM/lib/cmake/Qt6/QtPublicWasmToolchainHelpers.cmake")
emcc=$(emcc -dumpversion)
[ "$emcc" = "$wanted" ] ||
    fail "Qt $version wants Emscripten $wanted, but emcc is $emcc (emsdk install $wanted)"

mkdir -p "$build"

# cxx-qt-build asks the qmake it's given for Qt's paths and tools. The wasm
# Qt's own qmake runs the host's with a qt.conf of aqt's, which only works
# where aqt put the host Qt. This one runs it with a qt.conf of the paths
# here, and the tools of host-libexec.
#
# Its rcc compresses with zstd by default, which the wasm QtCore can't
# read (it lacks qResourceFeatureZstd, so the link fails). Qt's own CMake
# passes --no-zstd for the web, but cxx-qt-build has no way to, so
# host-libexec's rcc is a script that does; the other tools are links.
tools=$build/host-libexec
rm -rf "$tools"
mkdir -p "$tools"
for tool in "$(query QT_HOST_LIBEXECS)"/*; do
    ln -s "$tool" "$tools/$(basename "$tool")"
done
rm "$tools/rcc"
printf '#!/bin/sh\nexec "%s" --no-zstd "$@"\n' "$(query QT_HOST_LIBEXECS)/rcc" >"$tools/rcc"
chmod +x "$tools/rcc"

cat >"$build/qt.conf" <<EOF
[Paths]
Prefix=$QT_WASM
Documentation=doc
Headers=include
Libraries=lib
LibraryExecutables=libexec
Binaries=bin
Plugins=plugins
QmlImports=qml
ArchData=.
Data=.
Translations=translations
Examples=examples
Tests=tests
Settings=etc/xdg
HostPrefix=$(query QT_HOST_PREFIX)
HostBinaries=$(query QT_HOST_BINS)
HostLibraries=$(query QT_HOST_LIBS)
HostLibraryExecutables=$tools
HostData=$QT_WASM
Sysroot=
SysrootifyPrefix=false
TargetSpec=wasm-emscripten
HostSpec=$(query QMAKE_SPEC)
EOF
printf '#!/bin/sh\nexec "%s" -qtconf "%s" "$@"\n' "$(command -v "$qmake")" "$build/qt.conf" \
    >"$build/qmake"
chmod +x "$build/qmake"

# The web crate has a lock of its own (not committed): Koil's, so it builds
# with the same versions.
cp "$root/Cargo.lock" "$root/web/Cargo.lock"

# aqt doesn't keep qt-cmake executable.
sh "$QT_WASM/bin/qt-cmake" -S "$root/web" -B "$build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_HOST_PATH="$(query QT_HOST_PREFIX)" \
    -DQT_HOST_PATH_CMAKE_DIR="$(query QT_HOST_LIBS)/cmake" \
    -DKOIL_QMAKE="$build/qmake"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
cmake --build "$build" -j "$jobs"

rm -rf "$out"
mkdir -p "$out"
cp "$build/koil.js" "$build/koil.wasm" "$build/qtloader.js" "$out/"
cp "$root/web/index.html" "$out/index.html"
cp "$root/packaging/window-icon.png" "$out/icon.png"
echo "build-web.sh: built $out"
