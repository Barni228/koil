use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // Every .qml and .js file in qml/ is part of the QML module.
    let mut qml_files: Vec<String> = std::fs::read_dir("qml")
        .expect("qml/ should exist")
        .map(|entry| entry.expect("qml/ should be readable").path())
        .filter(|path| {
            path.extension()
                .is_some_and(|ext| ext == "qml" || ext == "js")
        })
        .map(|path| path.to_string_lossy().replace('\\', "/"))
        .collect();
    qml_files.sort();
    // Rebuild when a file is added or removed, not only when one changes.
    println!("cargo::rerun-if-changed=qml");

    CxxQtBuilder::new_qml_module(QmlModule::new("Koil").qml_files(qml_files))
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .files([
            "src/document.rs",
            "src/ffi.rs",
            "src/koil.rs",
            "src/system.rs",
        ])
        .cpp_file("cpp/native.cpp")
        .include_dir("cpp")
        .build();
}
