#include "web.h"
#include "koil/src/ffi.cxx.h"

#include <QtCore/QEvent>
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

} // namespace

// What the JavaScript below calls (on `Module`).
EMSCRIPTEN_BINDINGS(koil_web)
{
  emscripten::function("koilColorSchemeChanged", &colorSchemeChanged);
  emscripten::function("koilFilesPicked", &filesPicked);
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
