#include "native.h"
#include "koil/src/ffi.cxx.h"

#include <algorithm>
#include <cmath>
#include <optional>

#include <QtCore/QCoreApplication>
#include <QtCore/QJsonArray>
#include <QtCore/QJsonDocument>
#include <QtCore/QJsonObject>
#include <QtCore/QMimeData>
#include <QtCore/QPointer>
#include <QtCore/QSet>
#include <QtCore/QTimer>
#include <QtCore/QTranslator>
#include <QtGui/QAbstractTextDocumentLayout>
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
#include <QtGui/QTextBlockUserData>
#include <QtGui/QTextCursor>
#include <QtGui/QTextDocument>
#include <QtGui/QTextFrame>
#include <QtGui/QTextLayout>
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

// Whether a line's icon was last colored as pending (see setPendingLines),
// as its block's user data. None is as false.
struct ColoredAs : QTextBlockUserData
{
  bool pending = false;
};

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
    const bool isPending = pending.contains(currentBlock().blockNumber());
    auto* colored = dynamic_cast<ColoredAs*>(currentBlockUserData());
    if (!colored && isPending) {
      colored = new ColoredAs;
      setCurrentBlockUserData(colored);
    }
    if (colored)
      colored->pending = isPending;
    const QStringView trimmed = QStringView(text).trimmed();
    if (trimmed.isEmpty())
      return;
    qsizetype start = text.indexOf(trimmed.front());
    const qsizetype length =
      text.at(start).isHighSurrogate() && start + 1 < text.size() ? 2 : 1;
    const auto icon = icons.constFind(text.mid(start, length));
    if (icon != icons.cend()) {
      setFormat(start, length, isPending ? pendingIcon : *icon);
      start += length;
    }
    // A dir's name ends with a `/`, and so do the dirs in a pattern's
    // path (`src/main.rs`): all of it up to the last one is dirs.
    const qsizetype slash = text.lastIndexOf(u'/');
    if (slash >= start)
      setFormat(start, slash + 1 - start, directory);
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

// Whether a change to `document` is only to its format (see FormatOnly),
// which leaves its text as it was.
bool
formatOnly(const QTextDocument* document)
{
  return document->property("koilFormatOnly").toBool();
}

// While it lives, the changes to `document` are only to its format: its
// line format, or the margins of LongLines. So the text isn't colored again
// (see TextColors), nor taken as changed (see TextChanges).
class FormatOnly
{
public:
  explicit FormatOnly(QTextDocument* document)
    : document(document)
    , was(formatOnly(document))
  {
    document->setProperty("koilFormatOnly", true);
  }
  ~FormatOnly() { document->setProperty("koilFormatOnly", was); }

private:
  QTextDocument* document;
  bool was;
};

// The characters of `document` from `from` to `to`, as it keeps them (a
// block's end as a paragraph separator). Not through a QTextCursor, which
// lays out the line it's put in to find its x, all of a long one.
QString
textBetween(const QTextDocument* document, int from, int to)
{
  QString text;
  if (to - from < 4096) {
    text.reserve(qMax(0, to - from));
    for (int i = from; i < to; ++i)
      text.append(document->characterAt(i));
    return text;
  }
  for (QTextBlock block = document->findBlock(from); block.isValid() && block.position() < to;
       block = block.next()) {
    const int start = qMax(from, block.position());
    const int end = block.position() + block.length() - 1; // its paragraph separator
    if (qMin(to, end) > start)
      text += block.text().mid(start - block.position(), qMin(to, end) - start);
    if (to > end)
      text += QChar::ParagraphSeparator;
  }
  return text;
}

const QString textColorsName = QStringLiteral("koilTextColors");

// How much of a line syntax.rs colors (syntax::MAX_LENGTH).
constexpr int coloredLength = 3000;

// Colors a file's text (see setTextColors), following edits, as a
// QSyntaxHighlighter would, but a line's colors go to its layout as they
// are, where QSyntaxHighlighter goes through a format for each of its
// characters: 5 ms for a line of a megabyte, and every line again whenever
// the format of any changed, though only the first `coloredLength`
// characters of one get colors. Each line's state (in a /* */ comment, say)
// is its block's user state, as a QSyntaxHighlighter's.
class TextColors : public QObject
{
public:
  explicit TextColors(QTextDocument* document)
    : QObject(document)
  {
    setObjectName(textColorsName);
    connect(document, &QTextDocument::contentsChange, this, [this](int from, int, int added) {
      if (!formatOnly(this->document()))
        color(from, from + added);
    });
  }

  QTextDocument* document() const { return static_cast<QTextDocument*>(parent()); }

  // A format for each SyntaxKind, in its order.
  QList<QTextCharFormat> formats;
  SyntaxComments comments{ true, true };
  // Whether the lines must be colored again (see setTextColors).
  bool stale = false;

  // Colors the lines from `from` to `to`, and those after them for as long
  // as the state a line ends in changes (a /* */ goes on).
  void color(int from, int to)
  {
    bool next = false;
    for (QTextBlock block = document()->findBlock(from);
         block.isValid() && (block.position() <= to || next);
         block = block.next()) {
      const int state = block.userState();
      colorLine(block);
      next = block.userState() != state;
    }
  }

  // Colors all the lines again, or takes the colors away (`clear`), as
  // one edit (see recolor), if any changed: an edit block, even with
  // nothing in it, has the TextEdit take all of its text as changed.
  void recolor(bool clear = false)
  {
    auto* doc = document();
    const FormatOnly formatting(doc);
    doc->setLayoutEnabled(false);
    QTextCursor cursor(doc);
    bool editing = false;
    for (QTextBlock block = doc->begin(); block.isValid(); block = block.next()) {
      const auto colors = clear ? QList<QTextLayout::FormatRange>() : colorsOf(block);
      if (block.layout()->formats() == colors)
        continue;
      if (!editing)
        cursor.beginEditBlock();
      editing = true;
      setColors(block, colors);
    }
    if (editing)
      cursor.endEditBlock();
    doc->setLayoutEnabled(true);
  }

private:
  void colorLine(const QTextBlock& block) { setColors(block, colorsOf(block)); }

  // A line's colors, and its state as its block's user state.
  QList<QTextLayout::FormatRange> colorsOf(QTextBlock block)
  {
    const QString text =
      block.length() - 1 > coloredLength
        ? textBetween(document(), block.position(), block.position() + coloredLength)
        : block.text();
    const rust::Slice<const uint16_t> line(reinterpret_cast<const uint16_t*>(text.constData()),
                                           static_cast<size_t>(text.size()));
    const QTextBlock before = block.previous();
    rust::Vec<SyntaxSpan> spans;
    block.setUserState(
      syntaxSpans(line, before.isValid() ? before.userState() : -1, comments, spans));
    QList<QTextLayout::FormatRange> colors;
    for (const auto& span : spans)
      colors.append({ span.start, span.length, formats.value(static_cast<int>(span.kind)) });
    return colors;
  }

  // As QSyntaxHighlighter does: the layout has a line's formats, and the
  // line is laid out again (now, unless the change being made does it).
  void setColors(const QTextBlock& block, const QList<QTextLayout::FormatRange>& colors)
  {
    auto* layout = block.layout();
    if (layout->formats() == colors)
      return;
    layout->setFormats(colors);
    document()->markContentsDirty(block.position(), block.length());
  }
};

// The TextColors of a TextEdit's document (a QQuickTextDocument), if it has
// them.
TextColors*
textColorsOf(QObject* textDocument)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return nullptr;
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  return static_cast<TextColors*>(
    quickDocument->textDocument()->findChild<QObject*>(textColorsName, Qt::FindDirectChildrenOnly));
}

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
lineFormat(double height, double bottomMargin, double indent, double rightMargin)
{
  QTextBlockFormat format;
  format.setLineHeight(height, QTextBlockFormat::FixedHeight);
  format.setBottomMargin(bottomMargin);
  // A hanging indent: the first row at the margin less the indent.
  format.setLeftMargin(indent);
  format.setTextIndent(-indent);
  format.setRightMargin(rightMargin);
  return format;
}

// A TextEdit with more characters than this builds only the lines in view
// (QQuickTextEditPrivate::largeTextSizeThreshold).
constexpr qsizetype largeTextSize = 10000;

const QString longLinesName = QStringLiteral("koilLongLines");

class LongLines;

// A line too long for Qt (see LongLines), as its block's user data, which
// Qt deletes with the block: its length, which LongLines keeps the longest
// of.
struct LongLine : QTextBlockUserData
{
  explicit LongLine(LongLines* lines);
  ~LongLine() override;

  LongLines* lines;
  int length = 0;
};

// The lines of a document longer than `longLength` characters (see
// watchLongLines). Qt lays out and draws all of a line in view, however
// long, so they're hidden from it (QTextBlock::setVisible), which skips
// them, and a line after them gets a top margin as tall as their rows, so
// the lines Qt lays out stay on the grid, a row each (see place).
class LongLines : public QObject
{
public:
  LongLines(QTextDocument* document, int longLength)
    : QObject(document)
    , longLength(longLength)
    , start(document)
    , end(document)
  {
    setObjectName(longLinesName);
    connect(document, &QTextDocument::contentsChange, this, &LongLines::changed);
    changed(0, 0, document->characterCount());
  }

  ~LongLines() override
  {
    for (auto* line : std::as_const(lines))
      line->lines = nullptr;
  }

  QTextDocument* document() const { return static_cast<QTextDocument*>(parent()); }

  int longLength;
  QSet<LongLine*> lines;
  // The grid, as place was last given it.
  double lineHeight = 0;
  double bottomMargin = 0;
  int rowLength = 0;
  // Where the edits since the last place were, as cursors, which move with
  // the text, while `dirty`.
  QTextCursor start;
  QTextCursor end;
  bool dirty = false;
  // Whether a line may have a margin of place's.
  bool placed = false;

  // An edit from `from`, `added` long: the lines in it that are too long
  // are hidden from Qt, the others shown. It's called before Qt lays them
  // out, so it never lays out a long one. The lines around it are placed
  // later (see place), as a change to the format here would go into the
  // edit Qt is making.
  void changed(int from, int removed, int added)
  {
    Q_UNUSED(removed);
    if (formatOnly(document()))
      return;
    auto* doc = document();
    const int to = from + added;
    bool any = false;
    for (QTextBlock block = doc->findBlock(from); block.isValid() && block.position() <= to;
         block = block.next()) {
      const int length = block.length() - 1;
      const bool isLong = length > longLength;
      auto* line = dynamic_cast<LongLine*>(block.userData());
      if (isLong && !line && !block.userData()) {
        line = new LongLine(this);
        block.setUserData(line);
      } else if (!isLong && line) {
        block.setUserData(nullptr); // which deletes it
        line = nullptr;
      }
      if (line)
        line->length = length;
      if (block.isVisible() == isLong)
        block.setVisible(!isLong);
      any = any || isLong;
    }
    if (!any && !placed && lines.isEmpty())
      return;
    const int last = doc->characterCount() - 1;
    if (!dirty) {
      start.setPosition(qMin(from, last));
      end.setPosition(qMin(to, last));
      dirty = true;
      return;
    }
    if (from < start.position())
      start.setPosition(qMin(from, last));
    if (to > end.position())
      end.setPosition(qMin(to, last));
  }

  // How many rows `block` takes: one, unless lines wrap (`rowLength`
  // characters a row, in a line Qt doesn't lay out).
  int rowsOf(const QTextBlock& block) const
  {
    if (!rowLength)
      return 1;
    if (!block.isVisible())
      return qMax(1, (block.length() - 1 + rowLength - 1) / rowLength);
    document()->documentLayout()->blockBoundingRect(block); // laid out
    return qMax(1, block.layout()->lineCount());
  }

  // The row `block` starts on, counted from 0.
  int rowOf(const QTextBlock& block) const
  {
    if (!rowLength)
      return block.blockNumber();
    if (block.isVisible())
      return qRound(document()->documentLayout()->blockBoundingRect(block).top() / lineHeight);
    int rows = 0;
    QTextBlock before = block.previous();
    for (; before.isValid() && !before.isVisible(); before = before.previous())
      rows += rowsOf(before);
    return before.isValid() ? rowOf(before) + rowsOf(before) + rows : rows;
  }

  // The block row `row` is in (the last one, past the end).
  QTextBlock blockAtRow(int row) const
  {
    auto* doc = document();
    if (!rowLength)
      return doc->findBlockByNumber(qBound(0, row, doc->blockCount() - 1));
    int lo = 0, hi = doc->blockCount() - 1;
    while (lo < hi) {
      const int mid = (lo + hi + 1) / 2;
      if (rowOf(doc->findBlockByNumber(mid)) <= row)
        lo = mid;
      else
        hi = mid - 1;
    }
    return doc->findBlockByNumber(lo);
  }

  int longest() const
  {
    int n = 0;
    for (const auto* line : std::as_const(lines))
      n = qMax(n, line->length);
    return n;
  }

  // Gives each line Qt lays out after hidden ones a top margin as tall as
  // their rows (and the end of the document one after the last of them),
  // on a grid of rows `lineHeight` tall, of which Qt's lines are `height`
  // and the `bottomMargin` after it (see lineFormat), with `rowLength`
  // characters in a row of a hidden line while lines wrap (0 while they
  // don't). Only around the edits since it was last called, unless the
  // grid is new.
  void place(double height, double margin, int length)
  {
    const bool all = height != lineHeight || margin != bottomMargin || length != rowLength;
    lineHeight = height;
    bottomMargin = margin;
    rowLength = length;
    if (!placed && lines.isEmpty()) {
      dirty = false;
      return;
    }
    if (!all && !dirty)
      return;
    auto* doc = document();
    QTextBlock block = all ? doc->begin() : doc->findBlock(start.position());
    const int last = all ? doc->characterCount() : end.position();
    dirty = false;
    // The rows of the hidden lines right before, and whether a line Qt
    // lays out is before those.
    int rows = 0;
    QTextBlock before = block.previous();
    for (; before.isValid() && !before.isVisible(); before = before.previous())
      rows += rowsOf(before);
    bool after = before.isValid();
    const FormatOnly formatting(doc);
    // As one edit, if there's any: an edit block, even one with nothing in
    // it, has the TextEdit take all of its text as changed.
    QTextCursor cursor(doc);
    bool editing = false;
    const auto change = [&] {
      if (!editing)
        cursor.beginEditBlock();
      editing = true;
    };
    for (; block.isValid(); block = block.next()) {
      if (!block.isVisible()) {
        rows += rowsOf(block);
        continue;
      }
      // After a line Qt lays out, the margin between them is the larger
      // of its bottom margin and this one.
      const double top = rows ? (after ? bottomMargin : 0) + rows * lineHeight : 0;
      if (block.blockFormat().topMargin() != top) {
        change();
        QTextBlockFormat format;
        format.setTopMargin(top);
        QTextCursor(block).mergeBlockFormat(format);
      }
      after = true;
      rows = 0;
      if (block.position() > last)
        break; // the first line after the edits
    }
    if (!block.isValid()) {
      // Qt adds a line's bottom margin only before the next line it lays
      // out, so the end's has it too, else a long last line ended past the
      // text, and the view didn't scroll to it. In whole pixels, as Qt
      // rounds a frame's margins: up, so the text reaches the grid's end.
      const double bottom = rows ? std::ceil((after ? bottomMargin : 0) + rows * lineHeight) : 0;
      auto* root = doc->rootFrame();
      QTextFrameFormat format = root->frameFormat();
      if (format.bottomMargin() != bottom) {
        change();
        format.setBottomMargin(bottom);
        root->setFrameFormat(format);
      }
    }
    if (editing)
      cursor.endEditBlock();
    placed = !lines.isEmpty();
  }
};

LongLine::LongLine(LongLines* lines)
  : lines(lines)
{
  lines->lines.insert(this);
}

LongLine::~LongLine()
{
  if (lines)
    lines->lines.remove(this);
}

const QString textChangesName = QStringLiteral("koilTextChanges");

// What changed in a document's text since it was last taken (see
// watchTextChanges), as one change: [from, from + removed) of the text then
// became [from, from + added) of the text now.
class TextChanges : public QObject
{
public:
  explicit TextChanges(QTextDocument* document)
    : QObject(document)
    , length(document->characterCount() - 1)
  {
    setObjectName(textChangesName);
    connect(document, &QTextDocument::contentsChange, this, &TextChanges::changed);
  }

  // The text's length as it was last taken.
  int length;
  // -1 for no change.
  int from = -1;
  int removed = 0;
  int added = 0;

  void changed(int at, int charsRemoved, int charsAdded)
  {
    if (formatOnly(static_cast<QTextDocument*>(parent())))
      return;
    if (from < 0) {
      from = at;
      removed = charsRemoved;
      added = charsAdded;
      return;
    }
    // Both as one, with what's between them: where they end in the text
    // between them, and so in the text before and after.
    const int start = qMin(from, at);
    const int end = qMax(from + added, at + charsRemoved);
    const int wasRemoved = end - (added - removed) - start;
    added = end + (charsAdded - charsRemoved) - start;
    removed = wasRemoved;
    from = start;
  }

  // The change, as from, removed and the text added (as toPlainText gives
  // it), or nothing if there's none (or it's not `withText`), and starts
  // over.
  QStringList take(bool withText)
  {
    auto* doc = static_cast<QTextDocument*>(parent());
    const int now = doc->characterCount() - 1;
    QStringList change;
    if (from >= 0 && withText) {
      // Not the paragraph separator Qt keeps after the text.
      const int start = qMin(from, now);
      QString text = textBetween(doc, start, qMin(from + added, now));
      for (QChar& c : text) {
        switch (c.unicode()) {
          case 0xfdd0: // QTextBeginningOfFrame
          case 0xfdd1: // QTextEndOfFrame
          case QChar::ParagraphSeparator:
          case QChar::LineSeparator:
            c = u'\n';
            break;
          case QChar::Nbsp:
            c = u' ';
            break;
          default:
            break;
        }
      }
      change = { QString::number(start), QString::number(qMin(removed, length - start)), text };
    }
    from = -1;
    length = now;
    return change;
  }
};

// The LongLines of a TextEdit's document (a QQuickTextDocument), if it has
// any.
LongLines*
longLinesOf(QObject* textDocument)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return nullptr;
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  return static_cast<LongLines*>(
    quickDocument->textDocument()->findChild<QObject*>(longLinesName, Qt::FindDirectChildrenOnly));
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
setLineFormat(QObject* textDocument,
              double height,
              double bottomMargin,
              double indent,
              double rightMargin)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  // A highlighter colors every line again, and lays the document out after
  // each one it has colors for, as recolor says: turning wrapping off took
  // minutes in a colored file of 100,000 lines. So the layout waits.
  auto* document = quickDocument->textDocument();
  const FormatOnly formatting(document);
  document->setLayoutEnabled(false);
  QTextCursor cursor(document);
  cursor.select(QTextCursor::Document);
  cursor.mergeBlockFormat(lineFormat(height, bottomMargin, indent, rightMargin));
  document->setLayoutEnabled(true);
}

void
setText(QObject* textEdit,
        const QString& text,
        double height,
        double bottomMargin,
        double indent,
        double rightMargin)
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
  // The new text is colored as it goes in, with the colors as they are now.
  if (auto* colors = textColorsOf(textDocument))
    colors->stale = false;
  const bool undo = document->isUndoRedoEnabled();
  document->setUndoRedoEnabled(false);
  QTextCursor cursor(document);
  cursor.beginEditBlock();
  // Cleared, as setting the text does, rather than the old text selected
  // and removed: the document keeps the text it removes in its buffer
  // (letting it go only once the buffer is nearly full), where Qt's
  // positions are ints, so a gigabyte's file opened again after the
  // listing went past them, and crashed.
  document->clear();
  cursor.setBlockFormat(lineFormat(height, bottomMargin, indent, rightMargin));
  cursor.insertText(text);
  cursor.endEditBlock();
  document->setUndoRedoEnabled(undo);
  // As setting the text does: the cursor at the start, and for a long text,
  // only the lines in view built.
  item->setProperty("cursorPosition", 0);
  followTextLength(item);
}

void
replaceText(QObject* textEdit, int start, int end, const QString& text)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  if (!item)
    return;
  auto* quickDocument =
    qobject_cast<QQuickTextDocument*>(item->property("textDocument").value<QObject*>());
  if (!quickDocument)
    return;
  // As TextEdit's remove does, which is in bounds, and its insert, which a
  // cursor's insertText does after it removes the selection, in one edit
  // block. Both then update the cursor's rectangle only if the character
  // format there changed, which plain text's doesn't.
  auto* document = quickDocument->textDocument();
  const int last = document->characterCount() - 1;
  QTextCursor cursor(document);
  cursor.setPosition(qBound(0, start, last));
  cursor.setPosition(qBound(0, end, last), QTextCursor::KeepAnchor);
  cursor.insertText(text);
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
watchLongLines(QObject* textDocument, int longLength)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (quickDocument && !longLinesOf(textDocument))
    new LongLines(quickDocument->textDocument(), longLength);
}

void
placeLongLines(QObject* textDocument, double lineHeight, double bottomMargin, int rowLength)
{
  if (auto* lines = longLinesOf(textDocument))
    lines->place(lineHeight, bottomMargin, rowLength);
}

int
longestLine(QObject* textDocument)
{
  auto* lines = longLinesOf(textDocument);
  return lines ? lines->longest() : 0;
}

QString
longLineSpot(QObject* textDocument, int position)
{
  auto* lines = longLinesOf(textDocument);
  if (!lines || lines->lines.isEmpty())
    return {};
  const QTextBlock block = lines->document()->findBlock(position);
  if (!block.isValid() || block.isVisible())
    return {};
  int column = position - block.position();
  int row = lines->rowOf(block);
  if (lines->rowLength) {
    // Where a row ends is where the next one starts, but at the line's end.
    int rows = column / lines->rowLength;
    if (rows && rows * lines->rowLength == column && column == block.length() - 1)
      --rows;
    row += rows;
    column -= rows * lines->rowLength;
  }
  return QString::number(row) + u' ' + QString::number(column);
}

int
longLinePosition(QObject* textDocument, int row, double column)
{
  auto* lines = longLinesOf(textDocument);
  if (!lines || lines->lines.isEmpty() || row < 0)
    return -1;
  const QTextBlock block = lines->blockAtRow(row);
  if (!block.isValid() || block.isVisible())
    return -1;
  const int first = lines->rowOf(block), rows = lines->rowsOf(block);
  if (row >= first + rows)
    return -1;
  const int length = block.length() - 1;
  int from = 0, to = length;
  if (lines->rowLength) {
    from = (row - first) * lines->rowLength;
    // Not past a row's last character but in the last row: the position
    // after it is the next row's.
    to = row - first == rows - 1 ? length : from + lines->rowLength - 1;
  }
  int position = block.position() + from + qBound(0, qRound(column), to - from);
  if (position > block.position() && lines->document()->characterAt(position).isLowSurrogate())
    --position;
  return position;
}

QString
longLineRuns(QObject* textDocument, int firstRow, int lastRow, int firstColumn, int lastColumn)
{
  QJsonArray runs;
  auto* lines = longLinesOf(textDocument);
  if (!lines || lines->lines.isEmpty())
    return QStringLiteral("[]");
  auto* doc = lines->document();
  const int rowLength = lines->rowLength;
  QTextBlock block = lines->blockAtRow(qMax(0, firstRow));
  for (int row = lines->rowOf(block); block.isValid() && row <= lastRow; block = block.next()) {
    const int rows = lines->rowsOf(block);
    if (!block.isVisible()) {
      const int position = block.position(), length = block.length() - 1;
      // The highlighter's colors, in order.
      const auto formats = block.layout()->formats();
      for (int r = qMax(0, firstRow - row); r < rows && row + r <= lastRow; ++r) {
        const int rowStart = r * rowLength;
        const int rowEnd = rowLength ? qMin(length, rowStart + rowLength) : length;
        int from = qMin(rowEnd, rowStart + qMax(0, firstColumn));
        int to = qMin(rowEnd, rowStart + qMax(0, lastColumn));
        // Whole characters.
        if (from > 0 && from < to && doc->characterAt(position + from).isLowSurrogate())
          --from;
        if (to > from && to < length && doc->characterAt(position + to).isLowSurrogate())
          ++to;
        for (int at = from; at < to;) {
          // The format over `at` (they're apart: syntax::apart), until one
          // starts or ends.
          int next = to;
          QTextCharFormat format;
          for (const auto& range : formats) {
            if (range.start > at)
              next = qMin(next, range.start);
            else if (range.start + range.length > at) {
              format.merge(range.format);
              next = qMin(next, range.start + range.length);
            }
          }
          // A tab is a column, as every other character.
          QJsonObject run{
            { QStringLiteral("row"), row + r },
            { QStringLiteral("column"), at - rowStart },
            { QStringLiteral("text"),
              textBetween(doc, position + at, position + next).replace(u'\t', u' ') }
          };
          if (format.hasProperty(QTextFormat::ForegroundBrush))
            run.insert(QStringLiteral("color"), format.foreground().color().name(QColor::HexArgb));
          if (format.fontUnderline())
            run.insert(QStringLiteral("underline"), true);
          runs.append(run);
          at = next;
        }
      }
    }
    row += rows;
  }
  return QString::fromUtf8(QJsonDocument(runs).toJson(QJsonDocument::Compact));
}

void
watchTextChanges(QObject* textDocument)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (quickDocument && !quickDocument->textDocument()->findChild<QObject*>(
                         textChangesName, Qt::FindDirectChildrenOnly))
    new TextChanges(quickDocument->textDocument());
}

QStringList
takeTextChange(QObject* textDocument, bool withText)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return {};
  // No Q_OBJECT (so no moc), so it's found by name rather than by type.
  auto* changes = static_cast<TextChanges*>(quickDocument->textDocument()->findChild<QObject*>(
    textChangesName, Qt::FindDirectChildrenOnly));
  return changes ? changes->take(withText) : QStringList();
}

void
rebuildTextNodes(QObject* textEdit)
{
  if (textEdit)
    QMetaObject::invokeMethod(textEdit, "updateWholeDocument");
}

void
scrollToCursorInQml(QObject* textArea)
{
  // Qt's TextArea scrolls its Flickable to show its cursor rectangle (in a
  // private slot of its own), which is at the document's start in a line
  // it doesn't lay out (see LongLines).
  if (textArea)
    QObject::disconnect(textArea, SIGNAL(cursorRectangleChanged()), textArea, nullptr);
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
  // The lines colored otherwise than they're pending now: not only those
  // that were pending, as Qt colors a line as an edit reaches it, with the
  // pending lines it has then, and vim's edit is a remove and an insert,
  // between which lines are other numbers (a :s's preview, a few lines
  // longer at each key, left a file's icon white).
  highlighter->pending = pending;
  QSet<int> changed;
  for (auto block = highlighter->document()->begin(); block.isValid(); block = block.next()) {
    const auto* colored = dynamic_cast<ColoredAs*>(block.userData());
    if ((colored && colored->pending) != pending.contains(block.blockNumber()))
      changed.insert(block.blockNumber());
  }
  if (!changed.isEmpty())
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

void
setTextColors(QObject* textDocument, const QStringList& colors, const QString& fileName)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  if (!quickDocument)
    return;
  auto* textColors = textColorsOf(textDocument);
  if (colors.isEmpty()) {
    if (textColors) {
      textColors->recolor(true);
      delete textColors;
    }
    return;
  }
  QList<QTextCharFormat> formats;
  for (const auto& color : colors)
    formats.append(colored(color));
  const auto url = static_cast<int>(SyntaxKind::Url);
  if (url < formats.size())
    formats[url].setFontUnderline(true);
  const auto comments = syntaxComments(fileName);
  if (!textColors) {
    textColors = new TextColors(quickDocument->textDocument());
    textColors->formats = formats;
    textColors->comments = comments;
    textColors->recolor();
    return;
  }
  if (formats == textColors->formats && comments.hash == textColors->comments.hash &&
      comments.slashes == textColors->comments.slashes)
    return;
  textColors->formats = formats;
  textColors->comments = comments;
  // Once the event loop runs, as another file's name comes right before
  // its text, which setText colors as it puts it in (and then it isn't
  // stale): coloring the old text first laid out a long one again.
  textColors->stale = true;
  QTimer::singleShot(0, textColors, [textColors] {
    if (textColors->stale) {
      textColors->stale = false;
      textColors->recolor();
    }
  });
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
