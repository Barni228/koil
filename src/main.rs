// Release builds on Windows are GUI apps (no console window).
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod cli;
mod document;
mod ffi;
mod history;
#[cfg(target_os = "macos")]
mod install;
mod koil;
mod listing;
mod sizes;
mod system;

use cxx_qt_lib::{QByteArray, QGuiApplication, QQmlApplicationEngine, QString, QUrl};

/// JetBrains Mono NL from Nerd Fonts, so the listing's icons always show.
/// Every character is one column wide, but the icons are drawn bigger, over
/// the space after them (not the "Mono" variant, which shrinks them to one
/// column). It has no ligatures, which would draw several characters, like
/// the `=` line, as one. It's the editor's default font.
const NERD_FONT: &[u8] = include_bytes!("../fonts/JetBrainsMonoNLNerdFont-Regular.ttf");

/// The app's icon (see `scripts/make-icons.sh`). The exe has it on Windows
/// and the bundle on macOS, but not a bare binary (Linux, `cargo run`).
#[cfg(not(windows))]
const WINDOW_ICON: &[u8] = include_bytes!("../packaging/window-icon.png");

fn main() {
    // Before the app, so --help doesn't show it in the Dock, and a window
    // doesn't open for a command line Koil can't read.
    let mut args = cli::parse(std::env::args_os()).unwrap_or_else(|err| {
        cli::attach_console();
        err.exit()
    });
    cli::read_stdin(&mut args);
    *cli::ARGS.lock().unwrap() = args;

    let mut app = QGuiApplication::new();
    if let Some(mut app) = app.as_mut() {
        app.as_mut().set_application_name(&QString::from("Koil"));
        app.set_organization_name(&QString::from("Koil"));
    }
    ffi::use_settings_menu_title();
    ffi::use_nerd_font(&QByteArray::from(NERD_FONT));
    // In a bundle, macOS draws the Dock's icon from the bundle's, as Finder
    // does; a window icon would replace it.
    #[cfg(not(windows))]
    if !in_bundle() {
        ffi::use_window_icon(&QByteArray::from(WINDOW_ICON));
    }

    // Qt Quick's default Windows style has no dark theme. Fusion follows the
    // system's light or dark mode, title bar and menus included (FluentWinUI3
    // left those light). Setting QT_QUICK_CONTROLS_STYLE from here doesn't
    // work: Qt reads the C runtime's copy of the environment, made at startup.
    #[cfg(windows)]
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        ffi::set_controls_style(&QString::from("Fusion"));
    }

    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/Koil/qml/main.qml"));
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}

/// Whether Koil runs from a macOS app bundle (`Koil.app/Contents/MacOS`).
#[cfg(not(windows))]
fn in_bundle() -> bool {
    std::env::current_exe().is_ok_and(|exe| {
        exe.parent()
            .is_some_and(|dir| dir.ends_with("Contents/MacOS"))
    })
}
