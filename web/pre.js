// Runs in Koil's module as it starts, before its main (see docs/platform.md,
// Web, and CMakeLists.txt's --pre-js). Koil's home dir is kept in the
// browser's storage (IndexedDB): read in before Koil starts, and saved a
// moment after Koil writes it (koilSaveDisk, which web.cpp's saveWebDisk
// calls) and as the page is hidden. What's outside it (/tmp: the
// scratchpad's file, what an import brings in before it's in place, a
// folder's .zip on its way to a download) is in memory alone.

// Emscripten's HOME, which Rust's home_dir reads.
const koilHome = "/home/web_user";

Module.preRun = [].concat(Module.preRun || []);
Module.preRun.push(() => {
  FS.mkdirTree(koilHome);
  FS.mount(IDBFS, {}, koilHome);
  addRunDependency("koil-home");
  FS.syncfs(true, error => {
    if (error)
      console.error("Koil couldn't read its files from the browser's storage:", error);
    removeRunDependency("koil-home");
  });
});

// One save at a time (IndexedDB's), and another after it if Koil wrote
// meanwhile.
let koilSaving = false, koilSaveAgain = false, koilSaveTimer = 0;

function koilSave() {
  clearTimeout(koilSaveTimer);
  if (koilSaving) {
    koilSaveAgain = true;
    return;
  }
  koilSaving = true;
  FS.syncfs(false, error => {
    koilSaving = false;
    if (error)
      console.error("Koil couldn't save its files to the browser's storage:", error);
    if (koilSaveAgain) {
      koilSaveAgain = false;
      koilSave();
    }
  });
}

// A moment after the last write, so an apply's steps are saved at once.
Module.koilSaveDisk = () => {
  clearTimeout(koilSaveTimer);
  koilSaveTimer = setTimeout(koilSave, 300);
};

// The tab is put away or closed: now, as it may not run again.
addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden")
    koilSave();
});
addEventListener("pagehide", koilSave);
