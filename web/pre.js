// Runs in Koil's module as it starts, before its main (see docs/platform.md,
// Web, and CMakeLists.txt's --pre-js). Koil's home dir is kept in the
// browser's storage (IndexedDB): read in before Koil starts, and saved a
// moment after Koil writes it (koilSaveDisk, which web.cpp's saveWebDisk
// calls) and as the page is hidden. What's outside it (/tmp: the
// scratchpad's file, what an import brings in before it's in place, a
// folder's .zip on its way to a download) is in memory alone.
//
// A save makes the browser's storage what this tab has, deleting what it
// hasn't. So nothing is saved once another tab has taken Koil over
// (koilStopped, see index.html), nor if the files couldn't be read as Koil
// started: saving what's here then would delete them.

// Emscripten's HOME, which Rust's home_dir reads.
const koilHome = "/home/web_user";

let koilReadFailed = false;

// Koil's files can't be kept: says so in the console, and to Koil, which
// shows it (koilOnStorageProblem, set by web.cpp's watchWebStorage), or
// will once it watches (koilStorageProblem).
function koilCantKeep(why) {
  console.error(why);
  Module.koilStorageProblem = why;
  Module.koilOnStorageProblem?.(why);
}

Module.preRun = [].concat(Module.preRun || []);
Module.preRun.push(() => {
  FS.mkdirTree(koilHome);
  FS.mount(IDBFS, {}, koilHome);
  addRunDependency("koil-home");
  FS.syncfs(true, error => {
    if (error) {
      koilReadFailed = true;
      koilCantKeep(`Koil couldn't read its files from the browser's storage (${error}), so it `
        + "saves nothing now, which would replace them: reload the page to try again");
    }
    removeRunDependency("koil-home");
  });
});

// One save at a time (IndexedDB's), and another after it if Koil wrote
// meanwhile. `koilSaved` are what waits for the saves to end (koilSaveNow).
let koilSaving = false, koilSaveAgain = false, koilSaveTimer = 0, koilSaved = [];
let koilKeepAsked = false;

function koilSave() {
  clearTimeout(koilSaveTimer);
  if (koilReadFailed || globalThis.koilStopped) {
    koilSavesDone();
    return;
  }
  if (koilSaving) {
    koilSaveAgain = true;
    return;
  }
  koilSaving = true;
  FS.syncfs(false, error => {
    koilSaving = false;
    if (error)
      koilCantKeep(`Koil couldn't save its files to the browser's storage (${error})`);
    else
      koilKeep();
    if (koilSaveAgain) {
      koilSaveAgain = false;
      koilSave();
      return;
    }
    koilSavesDone();
  });
}

function koilSavesDone() {
  const waiting = koilSaved;
  koilSaved = [];
  for (const done of waiting)
    done();
}

// Asks the browser to keep the files (persistent storage): without that, a
// browser may delete a site's storage when the disk runs low, and Safari
// does after a week without a visit. Once, after the first save, as Firefox
// asks the user.
function koilKeep() {
  if (koilKeepAsked || !navigator.storage?.persist)
    return;
  koilKeepAsked = true;
  navigator.storage.persisted()
    .then(kept => kept || navigator.storage.persist())
    .catch(error => console.warn("Koil couldn't ask the browser to keep its files:", error));
}

// A moment after the last write, so an apply's steps are saved at once.
Module.koilSaveDisk = () => {
  clearTimeout(koilSaveTimer);
  koilSaveTimer = setTimeout(koilSave, 300);
};

// Saves now, and resolves once it's saved (or can't be): before another
// tab takes Koil over (see index.html).
Module.koilSaveNow = () => new Promise(done => {
  koilSaved.push(done);
  koilSave();
});

// The tab is put away or closed: now, as it may not run again.
addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden")
    koilSave();
});
addEventListener("pagehide", koilSave);
