# Platforms and packaging

- **App icon**: macOS draws icons as they are, so `icon.png` is on
  Apple's grid: 1024 pixels, with the rounded square in the middle 824.
  It's Apple's shape too, with continuous corners (UIBezierPath's, radius
  185.4, as in Apple's templates): macOS 26 puts an icon that isn't in a
  gray one (in Finder, Launchpad, the Dock). A new picture must be put on
  the grid first, as `make-icons.sh` only scales it, and crops it for
  Windows, whose icons nearly fill their square (90%). Qt gives windows
  the exe's `IDI_ICON1` on Windows; elsewhere `lib.rs` sets
  `window-icon.png` (the macOS one) as the window icon, for Linux and
  `cargo run` on macOS (its Dock icon), but not in the bundle
  (`in_bundle`), as on macOS it's the Dock's icon too, which then
  wouldn't be the one macOS draws from the bundle's, as Finder does.
- **cxx-qt**: bridges containing a `#[qobject]` declare `QObject` implicitly
  (declaring it again fails); plain bridges like `ffi.rs` must declare it
  themselves. `#[auto_cxx_name]` turns snake_case into camelCase for QML.
  qmlcachegen rejects `native` as a QML property name (hence `System`).
- **macOS**: `MACOSX_DEPLOYMENT_TARGET` is set to 13.0 in `bundle-macos.sh`.
  Without it, cc and rustc target the build machine's macOS version.
  `macdeployqt` breaks signatures, so the bundle is re-signed ad hoc. The
  Homebrew-only `macdeployqt` errors about QtSvg are harmless. It copies
  more than Koil loads, which `bundle-macos.sh` deletes (the `.dmg` went
  from 64 MB to 48 MB): every Controls style (macOS's falls back to Fusion,
  then Basic; the others are never loaded), QML modules no import of
  Koil's reaches (Particles, VectorImage, LocalStorage and the QtSql it
  links, …), and the plugins for images, TLS, network information, the
  widgets' style and databases (whose client libraries it can't find in
  CI: its "ERROR: no file at" lines, which it still prints).
  `package-windows.ps1` does the same with windeployqt's options
  (`--skip-plugin-types`, no translations, no shader compilers: Windows
  has D3D's, and DXC is D3D12's) and deletes, which also take the Windows
  style and NativeStyle, as Fusion is set there. That was checked without
  running it: Windows' Qt (`aqt install-qt windows desktop 6.10.3
  win64_msvc2022_64`, which unpacks on macOS too), its `qmldir`s for
  imports of what's deleted, and `objdump -p` for the DLLs Koil's imports,
  `qwindows.dll` and the QML plugins kept import. To check the list, build the bundle with
  CI's Qt (`aqt install-qt mac desktop 6.11.3 clang_64`, its `bin` first
  on `PATH`) and a temporary `Timer` that opens the windows and dialogs,
  run `Contents/MacOS/Koil` with `DYLD_PRINT_LIBRARIES=1`, and compare
  what's loaded from the bundle with and without the deletes. A new
  import (`QtQuick.Particles`), a picture (an `Image`) or a network
  request needs what's deleted for it put back.
- **Windows**: `lib.rs` sets the Fusion style (`QQuickStyle::setStyle`, unless
  `QT_QUICK_CONTROLS_STYLE` is set; setting that variable from Rust doesn't
  reach Qt, which reads the C runtime's startup copy), because the default
  "Windows" style has no dark theme (FluentWinUI3 left the title bar and menus
  light; Fusion doesn't). Fusion frames a TextArea like a text field, so
  Editor.qml replaces its background with a plain one. `build.rs` compiles
  the C++ with `/utf-8`: MSVC otherwise reads it in the system's code page,
  and qmlcachegen writes QML's strings into it as they are (the drop
  label's “%1” came out garbled). The MSVC CRT DLLs are
  copied app-locally, so no VC++ Redistributable is needed.
  `package-windows.ps1` loads the VS dev shell itself; `ilammy/msvc-dev-cmd`
  was removed because it's stuck on Node 20.
  While a `Popup.Window` is open (a `DropList`), Qt has the window it's in
  grab the mouse, so Windows sends that window the clicks, and Qt hands
  each to the popup first, then to the window if the popup didn't take
  it. Qt 6.10's popup windows never take a press (QTBUG-141362, fixed in
  6.11), so an item under a row took it from the row: a click on a shell
  in Settings opened the `:h shortcuts` link under the list. So
  `lib.rs` installs native.cpp's `PopupClickFilter` (`keepPopupClicks`),
  which drops a press a window gets where a popup window of its own
  is, with its moves and release (also a press on a popup's padding,
  which 6.11 still passes on). macOS sends the clicks to the popup's own
  window. QtQuickTest's `mouseClick` sends an event to a window
  directly, past that routing, so it can't show the bug: a C++
  `QTest::mouseClick` on the window under the list goes through it, as
  Windows' clicks do, and with Windows' Qt for macOS (CLAUDE.md's Build
  and test) shows the click reach the item under the row.
- **Web**: the web version is the same code, built with Qt for
  WebAssembly (single-threaded, the only one cxx-qt supports) into
  `koil.wasm`, which `web/index.html` loads with Qt's `qtloader.js`.
  `scripts/build-web.sh` builds it (CLAUDE.md's Build and test), and
  `scripts/web-smoke.mjs` checks it in headless Chrome. What's odd about
  the build, and why:
  - cxx-qt builds for the web only through CMake (`web/CMakeLists.txt`,
    with cxx-qt-cmake and Corrosion, which runs cargo): cargo alone can't
    link Qt's wasm. CMake links a static library, and Koil is a binary,
    so `web/` is a crate of its own (`koil_web`, a `staticlib`) whose
    `koil_main` calls `koil::run`, and `web/main.cpp` is the page's
    `main`, which calls that. Making Koil's own crate a `staticlib` too
    would have built a 400 MB library on every desktop build. Koil's C++
    and QML module reach `koil_web` by Koil's `links` key: `build.rs`
    exports them (`.export()`) on the web, and `web/build.rs` collects
    them into the initializers CMake links. `web/Cargo.lock` is a copy of
    Koil's, made by the script, so both build the same versions.
  - cxx-qt-build asks the qmake it's given for Qt's paths; the wasm Qt's
    own runs the host's with aqt's `qt.conf`, which only works where aqt
    put the host Qt. The script writes a `qt.conf` of its own, and a
    `qmake` that runs the host's with it.
  - The host's `rcc` compresses with zstd, which the wasm QtCore lacks
    (`qResourceFeatureZstd` is undefined at the link). Qt's own CMake
    passes `--no-zstd` for the web, but cxx-qt-build has no way to, so
    the script's `qt.conf` gives it tools of its own (`host-libexec`):
    the host's, but `rcc`, a script that adds `--no-zstd`.
  - Qt for the web is built with Emscripten's JavaScript exceptions, and
    Rust's std with wasm's own, which refer to a `__cpp_exception` tag
    that nothing defines then. Linking with `-fwasm-exceptions` to get it
    breaks Qt (`__resumeException`), so `web/cpp_exception_tag.S`
    defines the tag, as Emscripten's compiler-rt does. Nothing can throw
    it, so a panic can't unwind: it aborts Koil (the console says
    "_Unwind_RaiseException is not correctly implemented"), and the page
    says Koil stopped. If a Rust or Emscripten update breaks this, the
    way out is nightly Rust with `-Zbuild-std=std,panic_abort
    -Cpanic=abort`, or a Qt built with `-feature-wasm-exceptions`.
  - `app.exec()` throws to give the browser its loop back (Qt's runs in
    it), which Rust's frames take for a panic, so on the web `run`
    forgets the app and the engine and returns.
  - QML's imports are linked statically, those `qmlimportscanner` finds
    in `qml/` (`QT_QML_IMPORT_SCANNER_EXTRA_ROOT_PATHS`, as `qml/` isn't
    under `web/`). Without them, QtQuick's plugin isn't found.
  - Qt, Emscripten and the host Qt must be the very versions that go
    together: the host Qt's version is the wasm Qt's, and Emscripten is
    the one Qt names (`QT_EMCC_RECOMMENDED_VERSION`); the script checks
    both. `uzers` doesn't build for Emscripten, and the web has no users
    anyway, so `K` shows no owner or group there.
  - The web has no threads (`thread::spawn` fails, and unwrapping that
    aborts) and runs no processes. So koil-core walks the listing in one
    thread there; nothing watches the disk (`DiskWatcher`, `FileWatcher`:
    nothing but Koil changes it); dirs' sizes are counted at once, in
    the one thread, and again each time, as nothing tells what changed
    (`Sizes::want`; its disk is in memory, so it's quick); and shell
    commands, Open With and Reveal say the browser can't run other
    programs.
  - stdin isn't read (`cli::read_stdin`): Emscripten would ask for it
    with a prompt.
- **Web, keys**: in a browser on a Mac, Qt hands keys as macOS's Qt does
  (Cmd as Ctrl, Ctrl as Meta), so the web version acts as the Mac app
  there (`isMac`, from `System.webOnMac`, which reads `navigator`): Cmd
  for the menus' keys, `<D-…>` names, Ctrl for vim's. Its menus are
  WindowMenuBar's all the same (see Menus). There Qt gives Ctrl and a
  letter the letter as its text, where macOS gives a control character,
  so the editor would type it: insert mode drops one that the editor has
  no use for (`Vim.insertKey`, `macEditorKeys`: macOS's Ctrl-A, Ctrl-K…
  stay the editor's). Browsers keep some keys from pages, which then
  never reach Koil: Cmd+W, Cmd+T, Cmd+N and Cmd+Q on a Mac (Ctrl+W,
  Ctrl+T, Ctrl+N elsewhere), with Shift too, and Brave on a Mac keeps
  Ctrl+W (vim's `<C-w>`) as well. Koil doesn't fight them.
- **Web, windows**: Settings, Shortcuts and the help's window are windows
  of Qt's in the page, whose frames (a title bar with Qt's buttons, which
  moves them) Qt draws in its shadow DOM, light gray in either theme.
  `index.html` adds a style there that draws them in Koil's window color
  (`--window`). Koil gives the page its colors as they change (CSS
  variables and `data-theme` on the page's root, from web.cpp's
  `useWebPage`, at each change of the palette, as Qt's
  `colorSchemeChanged` doesn't come on the web), which the page's own
  colors follow too, the browser's mode until then.
