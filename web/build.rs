fn main() {
    // Koil's C++ and QML module come from what its build script exports
    // (by its links key): this collects them into the initializers that
    // CMakeLists.txt links in, as nothing calls them.
    cxx_qt_build::CxxQtBuilder::new().build();
}
