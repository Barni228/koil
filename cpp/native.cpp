#include "native.h"

#include <algorithm>

#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QTranslator>
#include <QtGui/QClipboard>
#include <QtGui/QFontDatabase>
#include <QtGui/QFontMetricsF>
#include <QtGui/QGuiApplication>
#include <QtGui/QSyntaxHighlighter>
#include <QtGui/QTextBlockFormat>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtQuick/QQuickTextDocument>
#include <QtQuickControls2/QQuickStyle>

namespace {

const QString dataFormat = QStringLiteral("application/x-koil-data");

class MacMenuTranslator : public QTranslator
{
public:
  using QTranslator::QTranslator;

  QString translate(const char* context,
                    const char* sourceText,
                    const char* disambiguation,
                    int n) const override
  {
    Q_UNUSED(disambiguation);
    Q_UNUSED(n);
    if (qstrcmp(context, "MAC_APPLICATION_MENU") == 0 &&
        qstrcmp(sourceText, "Preferences...") == 0) {
      return QStringLiteral("Settings…");
    }
    return {};
  }

  bool isEmpty() const override { return false; }
};

// Whether a family has Latin letters, digits and punctuation, all the same
// width. Not QFontDatabase::isFixedPitch: a font says it's monospaced only
// if every glyph is, so Nerd Fonts with wide icons (all but the "Mono"
// ones) don't, though their text is. It's also slower, since it (like
// writingSystems) loads every style of the family.
bool
hasFixedWidthText(const QString& family)
{
  QFont font(family);
  font.setPixelSize(40);
  font.setStyleStrategy(QFont::NoFontMerging); // no widths from other fonts
  const QFontMetricsF metrics(font);
  const qreal width = metrics.horizontalAdvance(QLatin1Char('M'));
  for (const QChar ch : QStringLiteral("iMW0.,_|"))
    if (!metrics.inFont(ch) || !qFuzzyCompare(metrics.horizontalAdvance(ch), width))
      return false;
  return width > 0;
}

const QString highlighterName = QStringLiteral("koilListingHighlighter");

// See setListingColors.
class ListingHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  QHash<QString, QTextCharFormat> icons;
  QTextCharFormat directory;
  QTextCharFormat rule;
  struct Span
  {
    int start;
    int length;
    QTextCharFormat format;
  };
  QList<Span> path;

protected:
  void highlightBlock(const QString& text) override
  {
    const QStringView trimmed = QStringView(text).trimmed();
    if (trimmed.isEmpty())
      return;
    if (trimmed.size() >= 3 &&
        std::all_of(trimmed.begin(), trimmed.end(), [](QChar c) { return c == u'='; })) {
      setFormat(0, text.size(), rule);
      return;
    }
    qsizetype start = text.indexOf(trimmed.front());
    if (currentBlock().blockNumber() == 0) {
      setFormat(start, text.size() - start, directory);
      for (const auto& span : std::as_const(path))
        setFormat(span.start, span.length, span.format);
      return;
    }
    const qsizetype length =
      text.at(start).isHighSurrogate() && start + 1 < text.size() ? 2 : 1;
    const auto icon = icons.constFind(text.mid(start, length));
    if (icon != icons.cend()) {
      setFormat(start, length, *icon);
      start += length;
    }
    if (trimmed.endsWith(u'/'))
      setFormat(start, text.size() - start, directory);
  }
};

ListingHighlighter*
highlighterOf(QObject* textDocument)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return nullptr;
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  return static_cast<ListingHighlighter*>(quickDocument->textDocument()->findChild<QSyntaxHighlighter*>(
    highlighterName, Qt::FindDirectChildrenOnly));
}

QTextCharFormat
colored(const QString& color)
{
  QTextCharFormat format;
  format.setForeground(QColor(color));
  return format;
}

} // namespace

void
useSettingsMenuTitle()
{
  auto* app = QCoreApplication::instance();
  app->installTranslator(new MacMenuTranslator(app));
}

void
useIconFallbackFont()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
  // Every Nerd Font has the same icons. The symbols-only one has nothing
  // else, and a "Mono" one's icons are one column wide, as the text is.
  const QStringList families = QFontDatabase::families();
  QString family;
  for (const auto& wanted : { QStringLiteral("Symbols Nerd Font Mono"),
                              QStringLiteral("Symbols Nerd Font"),
                              QStringLiteral("Nerd Font Mono"),
                              QStringLiteral("Nerd Font") }) {
    const auto found = std::find_if(families.cbegin(), families.cend(), [&](const QString& f) {
      return f.contains(wanted, Qt::CaseInsensitive);
    });
    if (found != families.cend()) {
      family = *found;
      break;
    }
  }
  // Private use characters have no script, which Qt treats as common.
  if (!family.isEmpty())
    QFontDatabase::addApplicationFallbackFontFamily(QChar::Script_Common, family);
#endif
}

void
setControlsStyle(const QString& style)
{
  QQuickStyle::setStyle(style);
}

QString
clipboardText()
{
  return QGuiApplication::clipboard()->text();
}

QString
clipboardData()
{
  const auto* data = QGuiApplication::clipboard()->mimeData();
  if (data && data->hasFormat(dataFormat))
    return QString::fromUtf8(data->data(dataFormat));
  return {};
}

void
setClipboardText(const QString& text, const QString& data)
{
  auto* mimeData = new QMimeData;
  mimeData->setText(text);
  if (!data.isEmpty())
    mimeData->setData(dataFormat, data.toUtf8());
  QGuiApplication::clipboard()->setMimeData(mimeData);
}

void
setLineFormat(QObject* textDocument, double height, double bottomMargin)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  QTextCursor cursor(quickDocument->textDocument());
  cursor.select(QTextCursor::Document);
  QTextBlockFormat format;
  format.setLineHeight(height, QTextBlockFormat::FixedHeight);
  format.setBottomMargin(bottomMargin);
  cursor.mergeBlockFormat(format);
}

void
setListingColors(QObject* textDocument,
                 const QStringList& iconColors,
                 const QString& directoryColor,
                 const QString& ruleColor)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  auto* document = quickDocument->textDocument();
  auto* highlighter = highlighterOf(textDocument);
  if (directoryColor.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  if (!highlighter) {
    highlighter = new ListingHighlighter(document);
    highlighter->setObjectName(highlighterName);
  }
  highlighter->icons.clear();
  for (qsizetype i = 0; i + 1 < iconColors.size(); i += 2)
    highlighter->icons.insert(iconColors.at(i), colored(iconColors.at(i + 1)));
  highlighter->directory = colored(directoryColor);
  highlighter->rule = colored(ruleColor);
  highlighter->rehighlight();
}

void
setPathColors(QObject* textDocument, const QStringList& spans)
{
  auto* highlighter = highlighterOf(textDocument);
  if (!highlighter)
    return;
  highlighter->path.clear();
  for (qsizetype i = 0; i + 2 < spans.size(); i += 3)
    highlighter->path.append({ spans.at(i).toInt(), spans.at(i + 1).toInt(), colored(spans.at(i + 2)) });
  highlighter->rehighlightBlock(highlighter->document()->firstBlock());
}

QStringList
monospaceFamilies()
{
  QStringList families;
  for (const auto& family : QFontDatabase::families())
    if (!QFontDatabase::isPrivateFamily(family) && hasFixedWidthText(family))
      families.append(family);
  return families;
}
