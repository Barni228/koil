#include "web.h"
#include "koil/src/ffi.cxx.h"

#include <QtCore/QEvent>
#include <QtCore/QMetaObject>
#include <QtGui/QGuiApplication>
#include <QtGui/QPalette>
#include <QtGui/QStyleHints>

#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>

#include <cstdint>
#include <string>

using emscripten::val;

namespace {

bool followsScheme = false;

// The browser's mode: dark, or else light.
bool
browserDark()
{
  return val::global("window")
    .call<val>("matchMedia", std::string("(prefers-color-scheme: dark)"))["matches"]
    .as<bool>();
}

void
colorSchemeChanged(bool dark)
{
  if (followsScheme)
    QGuiApplication::styleHints()->setColorScheme(dark ? Qt::ColorScheme::Dark
                                                       : Qt::ColorScheme::Light);
}

// Gives the page Koil's colors, as its palette has them now: its window's
// (the windows' frames), the text's on it, the editor's, and whether it's
// dark, for the frames' buttons.
void
showPageColors()
{
  const QPalette palette = QGuiApplication::palette();
  val root = val::global("document")["documentElement"];
  val style = root["style"];
  const auto color = [&](const char* name, QPalette::ColorRole role) {
    style.call<void>("setProperty", std::string(name), palette.color(role).name().toStdString());
  };
  color("--window", QPalette::Window);
  color("--window-text", QPalette::WindowText);
  color("--base", QPalette::Base);
  const bool dark = palette.color(QPalette::Window).lightness() < 128;
  root["dataset"].set("theme", std::string(dark ? "dark" : "light"));
}

// Shows the page Koil's colors again whenever the palette changes (Qt's
// colorSchemeChanged doesn't come on the web).
class PaletteWatcher : public QObject
{
public:
  using QObject::QObject;

protected:
  bool eventFilter(QObject* object, QEvent* event) override
  {
    if (event->type() == QEvent::ApplicationPaletteChange)
      showPageColors();
    return QObject::eventFilter(object, event);
  }
};

// What the picker gave (see pickWebFiles): `document` is the Document's
// address, which went through JavaScript as a number.
void
filesPicked(std::uintptr_t document, std::string error)
{
  webFilesPicked(reinterpret_cast<QObject*>(document), QString::fromStdString(error));
}

// Emits the signal `name` with `args` on the QObject at `address` (which
// went through JavaScript as a number).
template<typename... Args>
void
emitOn(std::uintptr_t address, const char* name, Args... args)
{
  QMetaObject::invokeMethod(reinterpret_cast<QObject*>(address), name, Q_ARG(Args, args)...);
}

void
clipboardRead(std::uintptr_t system, std::string text, std::string error)
{
  emitOn(system, "clipboardRead", QString::fromStdString(text), QString::fromStdString(error));
}

void
storageFailed(std::uintptr_t system, std::string why)
{
  emitOn(system, "storageFailed", QString::fromStdString(why));
}

void
webDragChanged(std::uintptr_t document, bool on)
{
  emitOn(document, "webDragChanged", on);
}

void
filesDropped(std::uintptr_t document, std::string error)
{
  emitOn(document, "filesDropped", QString::fromStdString(error));
}

} // namespace

// What the JavaScript below calls (on `Module`).
EMSCRIPTEN_BINDINGS(koil_web)
{
  emscripten::function("koilColorSchemeChanged", &colorSchemeChanged);
  emscripten::function("koilFilesPicked", &filesPicked);
  emscripten::function("koilClipboardRead", &clipboardRead);
  emscripten::function("koilStorageFailed", &storageFailed);
  emscripten::function("koilWebDragChanged", &webDragChanged);
  emscripten::function("koilFilesDropped", &filesDropped);
}

// clang-format off
EM_JS(void, koilJsListenToColorScheme, (), {
  matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", event => Module.koilColorSchemeChanged(event.matches));
});

EM_JS(void, koilJsSaveDisk, (), {
  Module.koilSaveDisk?.();
});

// Each file goes in `staging` at its path in what's picked (a folder's
// files under its name); a part that could climb out (`..`) is left out.
EM_JS(void, koilJsOpenPicker, (std::uintptr_t document, const char* staging, bool folder), {
  const dir = UTF8ToString(staging);
  const input = window.document.createElement("input");
  input.type = "file";
  input.multiple = true;
  input.webkitdirectory = folder;
  input.addEventListener("change", async () => {
    let error = "";
    try {
      for (const file of input.files) {
        const parts = (folder && file.webkitRelativePath || file.name).split("/")
          .filter(part => part && part !== "." && part !== "..");
        if (!parts.length)
          continue;
        FS.mkdirTree([dir].concat(parts.slice(0, -1)).join("/"));
        FS.writeFile([dir].concat(parts).join("/"), new Uint8Array(await file.arrayBuffer()));
      }
    } catch (e) {
      error = String(e?.message ?? e);
    }
    Module.koilFilesPicked(document, error);
  });
  input.click();
});

EM_JS(void, koilJsReadClipboard, (std::uintptr_t system), {
  const done = (text, error) => Module.koilClipboardRead(system, text, error);
  if (!navigator.clipboard?.readText) {
    done("", "this browser doesn't let pages read it");
    return;
  }
  navigator.clipboard.readText().then(text => done(text, ""), e => done("", String(e?.message ?? e)));
});

EM_JS(void, koilJsWatchStorage, (std::uintptr_t system), {
  Module.koilOnStorageProblem = why => Module.koilStorageFailed(system, why);
  if (Module.koilStorageProblem)
    Module.koilOnStorageProblem(Module.koilStorageProblem);
});

// Ahead of Qt's own handlers (capturing, on the window), which it then
// never gets: a drag of anything but files (text, a link) still goes to
// Qt. dragover comes every few hundred ms at most while a drag is over the
// page, and dragleave as it goes from one element to another, so the drag
// is taken to have left once dragover stops coming, or the pointer leaves
// the window. Drops are written one after another (`queue`), each in
// `staging`, which Koil empties as it brings it in.
EM_JS(void, koilJsWatchDrops, (std::uintptr_t document, const char* staging), {
  const dir = UTF8ToString(staging);
  const hasFiles = event => Array.from(event.dataTransfer?.types ?? []).includes("Files");
  let over = false, leaveTimer = 0, queue = Promise.resolve();
  const show = on => {
    clearTimeout(leaveTimer);
    if (over !== on) {
      over = on;
      Module.koilWebDragChanged(document, on);
    }
  };
  const take = event => {
    if (!hasFiles(event))
      return false;
    event.preventDefault();
    event.stopPropagation();
    return true;
  };
  const dragging = event => {
    if (!take(event))
      return;
    event.dataTransfer.dropEffect = "copy";
    show(true);
    leaveTimer = setTimeout(() => show(false), 600);
  };
  addEventListener("dragenter", dragging, true);
  addEventListener("dragover", dragging, true);
  addEventListener("dragleave", event => {
    const out = event.clientX <= 0 || event.clientY <= 0 || event.clientX >= innerWidth
      || event.clientY >= innerHeight;
    if (take(event) && out)
      show(false);
  }, true);

  const file = entry => new Promise((done, fail) => entry.file(done, fail));
  const entriesIn = async folder => {
    const reader = folder.createReader(), all = [];
    for (;;) {
      const some = await new Promise((done, fail) => reader.readEntries(done, fail));
      if (!some.length)
        return all;
      all.push(...some);
    }
  };
  // A folder with what's in it, also its empty folders (which a picker
  // doesn't give).
  const put = async (entry, at) => {
    if (entry.isDirectory) {
      FS.mkdirTree(at);
      for (const inside of await entriesIn(entry))
        await put(inside, at + "/" + inside.name);
    } else {
      FS.writeFile(at, new Uint8Array(await (await file(entry)).arrayBuffer()));
    }
  };
  const usable = name => name && name !== "." && name !== ".." && !name.includes("/");
  addEventListener("drop", event => {
    if (!take(event))
      return;
    show(false);
    // Now: the event's items are gone once it's handled.
    const entries = Array.from(event.dataTransfer.items)
      .map(item => item.webkitGetAsEntry?.()).filter(entry => entry && usable(entry.name));
    const files = entries.length ? [] : Array.from(event.dataTransfer.files).filter(f => usable(f.name));
    queue = queue.then(async () => {
      let error = "";
      try {
        FS.mkdirTree(dir);
        for (const entry of entries)
          await put(entry, dir + "/" + entry.name);
        for (const f of files)
          FS.writeFile(dir + "/" + f.name, new Uint8Array(await f.arrayBuffer()));
      } catch (e) {
        error = String(e?.message ?? e);
      }
      Module.koilFilesDropped(document, error);
    });
  }, true);
});

EM_JS(void, koilJsDownload, (const char* path, const char* name, bool remove), {
  const at = UTF8ToString(path);
  const data = FS.readFile(at);
  if (remove)
    FS.unlink(at);
  const url = URL.createObjectURL(new Blob([data]));
  const link = window.document.createElement("a");
  link.href = url;
  link.download = UTF8ToString(name);
  link.click();
  // Once the download has it.
  setTimeout(() => URL.revokeObjectURL(url), 60000);
});
// clang-format on

void
useWebPage()
{
  qApp->installEventFilter(new PaletteWatcher(qApp));
  showPageColors();
}

bool
webOnMac()
{
  val navigator = val::global("navigator");
  val data = navigator["userAgentData"];
  std::string platform = data.isUndefined() ? navigator["platform"].as<std::string>()
                                            : data["platform"].as<std::string>();
  return platform.rfind("Mac", 0) == 0 || platform == "macOS";
}

void
followBrowserColorScheme(bool on)
{
  static bool listening = false;
  if (!listening) {
    koilJsListenToColorScheme();
    listening = true;
  }
  followsScheme = on;
  colorSchemeChanged(browserDark());
}

void
saveWebDisk()
{
  koilJsSaveDisk();
}

void
pickWebFiles(QObject* document, const QString& staging, bool folder)
{
  koilJsOpenPicker(reinterpret_cast<std::uintptr_t>(document), staging.toStdString().c_str(), folder);
}

void
downloadWebFile(const QString& path, const QString& name, bool remove)
{
  koilJsDownload(path.toStdString().c_str(), name.toStdString().c_str(), remove);
}

void
readWebClipboard(QObject* system)
{
  koilJsReadClipboard(reinterpret_cast<std::uintptr_t>(system));
}

void
watchWebStorage(QObject* system)
{
  koilJsWatchStorage(reinterpret_cast<std::uintptr_t>(system));
}

void
watchWebDrops(QObject* document, const QString& staging)
{
  koilJsWatchDrops(reinterpret_cast<std::uintptr_t>(document), staging.toStdString().c_str());
}
