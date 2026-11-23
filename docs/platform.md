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
