# The web build: Qt for WebAssembly links Koil (the koil_web crate, a static
# library) into koil.wasm. scripts/build-web.sh configures it with the
# wasm Qt's qt-cmake; see docs/platform.md, Web, for why each odd piece is
# here.
cmake_minimum_required(VERSION 3.24)
project(koil_web LANGUAGES CXX ASM)

set(Rust_CARGO_TARGET wasm32-unknown-emscripten)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

# cxx-qt builds for the web only this way (Corrosion runs cargo): cargo
# alone can't link Qt's wasm.
include(FetchContent)
FetchContent_Declare(CxxQt
    GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
    GIT_TAG 0.10.0)
FetchContent_MakeAvailable(CxxQt)

# The qmake that cxx-qt-build asks for Qt's paths: the wasm Qt's, not the
# host's, which it finds otherwise. scripts/build-web.sh makes one (see
# there why).
set(KOIL_QMAKE "${QT6_INSTALL_PREFIX}/bin/qmake" CACHE FILEPATH
    "The qmake of the wasm Qt that cxx-qt-build asks")

set(QT_MODULES Qt::Core Qt::Gui Qt::Qml Qt::Quick Qt::QuickControls2)
cxx_qt_import_crate(
    MANIFEST_PATH Cargo.toml
    CRATES koil_web
    QMAKE ${KOIL_QMAKE}
    QT_MODULES ${QT_MODULES})
cxx_qt_import_qml_module(koil_qml_module URI "Koil" SOURCE_CRATE koil_web)

# koil.js and koil.wasm (koil_web is the crate's target).
qt_add_executable(koil main.cpp cpp_exception_tag.S)
# The tag's .S needs wasm's exception instructions to assemble.
set_source_files_properties(cpp_exception_tag.S
    PROPERTIES COMPILE_OPTIONS "-mexception-handling")
target_link_libraries(koil PRIVATE koil_qml_module ${QT_MODULES})
# What Koil's QML imports (QtQuick.Controls and the rest) is linked
# statically, and only what it imports: what the scanner finds in qml/,
# which isn't under this dir.
set_target_properties(koil PROPERTIES
    QT_QML_IMPORT_SCANNER_EXTRA_ROOT_PATHS ${CMAKE_CURRENT_SOURCE_DIR}/../qml)
qt_import_qml_plugins(koil)
