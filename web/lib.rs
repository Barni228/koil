//! Koil on the web: main.cpp, the page's `main`, calls `koil_main`.

/// Starts Koil, and returns once its window is open (see `koil::run`).
#[unsafe(no_mangle)]
pub extern "C" fn koil_main() {
    koil::run();
}
