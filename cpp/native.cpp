#include "native.h"
#include "koil/src/ffi.cxx.h"

#include <algorithm>
#include <optional>

#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QPointer>
#include <QtCore/QSet>
#include <QtCore/QTranslator>
#include <QtGui/QClipboard>
#include <QtGui/QFileOpenEvent>
#include <QtGui/QFontDatabase>
#include <QtGui/QFontMetricsF>
#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtGui/QImage>
#include <QtGui/QPixmap>
#include <QtGui/QSyntaxHighlighter>
#include <QtGui/QTextBlockFormat>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickTextDocument>
#include <QtQuick/QQuickWindow>
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

// Hands the files the system asks the app to open (macOS's Open With) to
// `document`'s fileOpened signal.
class FileOpenFilter : public QObject
{
public:
  explicit FileOpenFilter(QObject* document)
    : QObject(document)
    , document(document)
  {
  }

  bool eventFilter(QObject* watched, QEvent* event) override
  {
    if (event->type() != QEvent::FileOpen)
      return QObject::eventFilter(watched, event);
    const auto* open = static_cast<QFileOpenEvent*>(event);
    const QString path = open->file().isEmpty() ? open->url().toLocalFile() : open->file();
    if (document && !path.isEmpty())
      fileOpened(document, path);
    return true;
  }

private:
  QPointer<QObject> document;
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

const QString keywordHighlighterName = QStringLiteral("koilKeywordHighlighter");

// See setKeywordColors.
class KeywordHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  QHash<QString, QTextCharFormat> keywords;

protected:
  void highlightBlock(const QString& text) override
  {
    qsizetype start = 0;
    const auto skipSpaces = [&] {
      while (start < text.size() && text.at(start).isSpace())
        ++start;
    };
    skipSpaces();
    if (start == text.size())
      return;
    // The box before a line to pick from, a Nerd Font icon.
    const bool pair = text.at(start).isHighSurrogate() && start + 1 < text.size();
    const char32_t first =
      pair ? QChar::surrogateToUcs4(text.at(start), text.at(start + 1)) : text.at(start).unicode();
    if (QChar::category(first) == QChar::Other_PrivateUse) {
      start += pair ? 2 : 1;
      skipSpaces();
    }
    qsizetype end = start;
    while (end < text.size() && !text.at(end).isSpace())
      ++end;
    const auto keyword = keywords.constFind(text.mid(start, end - start));
    if (keyword != keywords.cend())
      setFormat(start, end - start, *keyword);
  }
};

// Colors the document's lines again: the ones in `lines` (numbers, from
// 0), or all of them. It's one edit, so the text's change signals (and what
// QML does on them) come once, not once a line. QSyntaxHighlighter also
// lays the document out again after each line whose colors change, which
// took a second for all of a few thousand lines, so for more than a few the
// layout waits until the end, and is done once.
void
recolor(QSyntaxHighlighter* highlighter, const std::optional<QSet<int>>& lines = std::nullopt)
{
  auto* document = highlighter->document();
  const bool many = !lines || lines->size() > 20;
  if (many)
    document->setLayoutEnabled(false);
  if (lines) {
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (const int line : *lines)
      highlighter->rehighlightBlock(document->findBlockByNumber(line));
    cursor.endEditBlock();
  } else {
    highlighter->rehighlight();
  }
  if (many)
    document->setLayoutEnabled(true);
}

// The format setLineFormat gives every line.
QTextBlockFormat
lineFormat(double height, double bottomMargin)
{
  QTextBlockFormat format;
  format.setLineHeight(height, QTextBlockFormat::FixedHeight);
  format.setBottomMargin(bottomMargin);
  return format;
}

// A TextEdit with more characters than this builds only the lines in view
// (QQuickTextEditPrivate::largeTextSizeThreshold).
constexpr qsizetype largeTextSize = 10000;

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

void
useWindowIcon(const QByteArray& png)
{
  QGuiApplication::setWindowIcon(QIcon(QPixmap::fromImage(QImage::fromData(png, "PNG"))));
}

void
watchFileOpens(QObject* document)
{
  // A child of `document`, so it goes (and stops filtering) with it.
  qApp->installEventFilter(new FileOpenFilter(document));
}

#ifndef Q_OS_MACOS
// macOS's are in finder_mac.mm.
void
watchFinderService(QObject*)
{
}

QString
finderServiceShortcut()
{
  return {};
}
#endif

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
  cursor.mergeBlockFormat(lineFormat(height, bottomMargin));
}

void
setText(QObject* textEdit, const QString& text, double height, double bottomMargin)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  if (!item)
    return;
  auto* textDocument = item->property("textDocument").value<QObject*>();
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  // The old text out and the new one in, after a line in the format (which
  // every line it makes takes on), in an edit block: the document tells its
  // layout and the TextEdit when it ends. Emptying the TextEdit first (the
  // way setting its text does) changed its width, as the scroll bar went,
  // and that laid out the new text again.
  auto* document = quickDocument->textDocument();
  const bool undo = document->isUndoRedoEnabled();
  document->setUndoRedoEnabled(false);
  QTextCursor cursor(document);
  cursor.beginEditBlock();
  cursor.select(QTextCursor::Document);
  cursor.removeSelectedText();
  cursor.setBlockFormat(lineFormat(height, bottomMargin));
  cursor.insertText(text);
  cursor.endEditBlock();
  document->setUndoRedoEnabled(false); // which lets the old text go
  document->setUndoRedoEnabled(undo);
  // As setting the text does: the cursor at the start, and for a long text,
  // only the lines in view built.
  item->setProperty("cursorPosition", 0);
  followTextLength(item);
}

void
followTextLength(QObject* textEdit)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  if (!item)
    return;
  const bool large = item->property("length").toInt() > largeTextSize;
  if (large == item->flags().testFlag(QQuickItem::ItemObservesViewport))
    return;
  item->setFlag(QQuickItem::ItemObservesViewport, large);
  // The lines built again. A short text had all its lines built, from its
  // start, so marking them all changed builds just those in view, without
  // laying out the long text again. A long text's built lines start at the
  // view, and Qt builds again only from there, which may be past the end of
  // the text now, so a short one starts over (q_invalidate, which lays it
  // out again, quickly, as it's short).
  QMetaObject::invokeMethod(item, large ? "updateWholeDocument" : "q_invalidate");
}

void
redrawText(QObject* textEdit)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  if (!item || !item->window() || !(item->flags() & QQuickItem::ItemObservesViewport))
    return;
  // q_invalidate (a slot of Qt's, not public) is what Qt runs when fonts
  // change. It must run right before the frame is synced: a change after it
  // (to the text, its colors or the selection) asks for the changed lines
  // only, as before.
  QObject::connect(
    item->window(),
    &QQuickWindow::afterAnimating,
    item,
    [item] { QMetaObject::invokeMethod(item, "q_invalidate"); },
    Qt::SingleShotConnection);
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
  QHash<QString, QTextCharFormat> icons;
  for (qsizetype i = 0; i + 1 < iconColors.size(); i += 2)
    icons.insert(iconColors.at(i), colored(iconColors.at(i + 1)));
  const auto pendingIcon = colored(pendingIconColor);
  const auto directory = colored(directoryColor);
  if (icons == highlighter->icons && pendingIcon == highlighter->pendingIcon &&
      directory == highlighter->directory)
    return;
  highlighter->icons = icons;
  highlighter->pendingIcon = pendingIcon;
  highlighter->directory = directory;
  recolor(highlighter);
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
  // The lines that were pending or are now, but not both.
  QSet<int> changed = pending;
  changed.unite(highlighter->pending);
  changed.subtract(QSet<int>(pending).intersect(highlighter->pending));
  highlighter->pending = pending;
  recolor(highlighter, changed);
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
  recolor(highlighter);
}

void
setKeywordColors(QObject* textDocument, const QStringList& keywordColors)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  auto* document = quickDocument->textDocument();
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  auto* highlighter = static_cast<KeywordHighlighter*>(
    document->findChild<QSyntaxHighlighter*>(keywordHighlighterName, Qt::FindDirectChildrenOnly));
  if (keywordColors.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  if (!highlighter) {
    highlighter = new KeywordHighlighter(document);
    highlighter->setObjectName(keywordHighlighterName);
  }
  QHash<QString, QTextCharFormat> keywords;
  for (qsizetype i = 0; i + 1 < keywordColors.size(); i += 2)
    keywords.insert(keywordColors.at(i), colored(keywordColors.at(i + 1)));
  if (keywords == highlighter->keywords)
    return;
  highlighter->keywords = keywords;
  recolor(highlighter);
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
