#include "native.h"

#include <algorithm>

#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QSet>
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

// The font useNerdFont added (-1: none).
int nerdFontId = -1;

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

// See setListingColors and setPathColors.
class ListingHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  // Whether it colors the path field (setPathColors) rather than the
  // listing.
  bool isPath = false;
  QHash<QString, QTextCharFormat> icons;
  // The icon of a pending entry: one on a line in `pending` (see
  // setPendingLines).
  QTextCharFormat pendingIcon;
  QSet<int> pending;
  QTextCharFormat directory;
  struct Span
  {
    int start;
    int length;
    QTextCharFormat format;
  };
  QList<Span> spans;

protected:
  void highlightBlock(const QString& text) override
  {
    if (isPath) {
      setFormat(0, text.size(), directory);
      if (currentBlock().blockNumber() == 0)
        for (const auto& span : std::as_const(spans))
          setFormat(span.start, span.length, span.format);
      return;
    }
    const QStringView trimmed = QStringView(text).trimmed();
    if (trimmed.isEmpty())
      return;
    qsizetype start = text.indexOf(trimmed.front());
    const qsizetype length =
      text.at(start).isHighSurrogate() && start + 1 < text.size() ? 2 : 1;
    const auto icon = icons.constFind(text.mid(start, length));
    if (icon != icons.cend()) {
      setFormat(start, length, pending.contains(currentBlock().blockNumber()) ? pendingIcon : *icon);
      start += length;
    }
    if (trimmed.endsWith(u'/'))
      setFormat(start, text.size() - start, directory);
  }
};

// The highlighter of a TextEdit's document (a QQuickTextDocument), if it
// has one, or else a new one if `create` is set.
ListingHighlighter*
highlighterOf(QObject* textDocument, bool create)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return nullptr;
  auto* document = quickDocument->textDocument();
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  auto* highlighter = static_cast<ListingHighlighter*>(
    document->findChild<QSyntaxHighlighter*>(highlighterName, Qt::FindDirectChildrenOnly));
  if (!highlighter && create) {
    highlighter = new ListingHighlighter(document);
    highlighter->setObjectName(highlighterName);
  }
  return highlighter;
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
useNerdFont(const QByteArray& data)
{
  nerdFontId = QFontDatabase::addApplicationFontFromData(data);
#if QT_VERSION >= QT_VERSION_CHECK(6, 8, 0)
  // Private use characters have no script, which Qt treats as common.
  const QString family = nerdFontFamily();
  if (!family.isEmpty())
    QFontDatabase::addApplicationFallbackFontFamily(QChar::Script_Common, family);
#endif
}

QString
nerdFontFamily()
{
  // The font has a family name for old systems and one for new ones, and
  // which one Qt uses depends on the platform.
  return QFontDatabase::applicationFontFamilies(nerdFontId).value(0);
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
                 const QString& pendingIconColor,
                 const QString& directoryColor)
{
  auto* highlighter = highlighterOf(textDocument, !directoryColor.isEmpty());
  if (!highlighter)
    return;
  if (directoryColor.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  highlighter->icons.clear();
  for (qsizetype i = 0; i + 1 < iconColors.size(); i += 2)
    highlighter->icons.insert(iconColors.at(i), colored(iconColors.at(i + 1)));
  highlighter->pendingIcon = colored(pendingIconColor);
  highlighter->directory = colored(directoryColor);
  highlighter->rehighlight();
}

void
setPendingLines(QObject* textDocument, const QStringList& lines)
{
  auto* highlighter = highlighterOf(textDocument, false);
  if (!highlighter || highlighter->isPath)
    return;
  QSet<int> pending;
  for (const auto& line : lines)
    pending.insert(line.toInt());
  if (pending == highlighter->pending)
    return;
  highlighter->pending = pending;
  highlighter->rehighlight();
}

void
setPathColors(QObject* textDocument, const QString& directoryColor, const QStringList& spans)
{
  auto* highlighter = highlighterOf(textDocument, true);
  if (!highlighter)
    return;
  highlighter->isPath = true;
  highlighter->directory = colored(directoryColor);
  highlighter->spans.clear();
  for (qsizetype i = 0; i + 2 < spans.size(); i += 3)
    highlighter->spans.append({ spans.at(i).toInt(), spans.at(i + 1).toInt(), colored(spans.at(i + 2)) });
  highlighter->rehighlight();
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
