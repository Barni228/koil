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

    let builder = CxxQtBuilder::new_qml_module(QmlModule::new("Koil").qml_files(qml_files));
    // MSVC reads a source file in the system's code page unless told it's
    // UTF-8, which garbled qmlcachegen's string literals (the drop label's
    // “%1”).
    // SAFETY: only adds a flag, which cxx-qt-build sets nothing against.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
                cc.flag("/utf-8");
            }
        })
    };
    let builder = builder
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
        .include_dir("cpp");
    match std::env::var("CARGO_CFG_TARGET_OS").as_deref() {
        // The "Open in Koil" service and the apps of Open With on macOS
        // (Objective-C++, for AppKit).
        Ok("macos") => {
            builder.cpp_file("cpp/finder_mac.mm").build();
            println!("cargo::rustc-link-lib=framework=AppKit");
        }
        // The apps of Explorer's Open With, through the shell's COM
        // interfaces (uuid has their IDs, as BHID_DataObject).
        Ok("windows") => {
            builder.cpp_file("cpp/apps_win.cpp").build();
            for lib in ["shell32", "shlwapi", "ole32", "uuid"] {
                println!("cargo::rustc-link-lib={lib}");
            }
        }
        _ => {
            builder.build();
        }
    }

    // The exe's icon on Windows (nothing elsewhere).
    println!("cargo::rerun-if-changed=packaging/windows/koil.ico");
    embed_resource::compile("packaging/windows/koil.rc", embed_resource::NONE)
        .manifest_optional()
        .expect("koil.rc should compile");
}
