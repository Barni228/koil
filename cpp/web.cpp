#include "web.h"

#include <QtCore/QEvent>
#include <QtGui/QGuiApplication>
#include <QtGui/QPalette>
#include <QtGui/QStyleHints>

#include <emscripten.h>
#include <emscripten/bind.h>
#include <emscripten/val.h>

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

} // namespace

// What the JavaScript below calls (on `Module`).
EMSCRIPTEN_BINDINGS(koil_web)
{
  emscripten::function("koilColorSchemeChanged", &colorSchemeChanged);
}

// clang-format off
EM_JS(void, koilJsListenToColorScheme, (), {
  matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", event => Module.koilColorSchemeChanged(event.matches));
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
