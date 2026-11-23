# The tag of C++ exceptions, as wasm's native exceptions throw them. Rust's
# std (built with them) refers to it, but Qt for the web is built with
# Emscripten's JavaScript exceptions, which don't define it, and linking
# with -fwasm-exceptions to get it breaks Qt. Defined as Emscripten's
# compiler-rt does. Nothing throws it: a panic aborts (see docs/platform.md,
# Web).
.globl __cpp_exception
.tagtype __cpp_exception i32
__cpp_exception:
