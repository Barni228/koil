// The page's main: Emscripten calls it once the wasm is loaded. Koil's
// Rust is a static library, so it can't have a main of its own.
extern "C" void koil_main();

int main()
{
    koil_main();
    // Returning keeps the page running (Emscripten keeps the runtime alive
    // without EXIT_RUNTIME), with Qt's event loop in the browser's.
    return 0;
}
