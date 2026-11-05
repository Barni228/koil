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
#include <QtGui/QKeyEvent>
#include <QtGui/QPainter>
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

#ifdef Q_OS_MACOS
// Has Cmd+Backspace in a TextInput delete back to its start (see
// useLineDeleteKey). An application's filter, as the key goes to the item
// through it, before its Keys handlers and its own keyPressEvent.
class LineDeleteFilter : public QObject
{
public:
  using QObject::QObject;

  bool eventFilter(QObject* watched, QEvent* event) override
  {
    if (event->type() != QEvent::KeyPress || !watched->inherits("QQuickTextInput") ||
        watched->property("readOnly").toBool())
      return false;
    const auto* key = static_cast<QKeyEvent*>(event);
    // Qt's ControlModifier is Cmd on macOS.
    if (key->key() != Qt::Key_Backspace || key->modifiers() != Qt::ControlModifier)
      return false;
    int start = watched->property("selectionStart").toInt();
    int end = watched->property("selectionEnd").toInt();
    if (start == end) {
      start = 0;
      end = watched->property("cursorPosition").toInt();
    }
    // Nothing to delete: its Keys handlers have it (the help's search
    // closes on a Backspace in an empty field).
    if (start == end)
      return false;
    // TextInput's own, so Cmd+Z undoes it.
    QMetaObject::invokeMethod(watched, "remove", Q_ARG(int, start), Q_ARG(int, end));
    return true;
  }
};
#endif

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

// Whether a line was last colored as pending and as a file that can be
// run (see setEntryLines), as its block's user data. None is as neither.
struct ColoredAs : QTextBlockUserData
{
  bool pending = false;
  bool executable = false;
};

// See setListingColors and setPathColors.
class ListingHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  static inline const QString name = QStringLiteral("koilListingHighlighter");

  // Whether it colors the path field (setPathColors) rather than the
  // listing.
  bool isPath = false;
  QHash<QString, QTextCharFormat> icons;
  // The icon of a pending entry: one on a line in `pending`, and the name
  // of a file that can be run, on a line in `executable` (see
  // setEntryLines).
  QTextCharFormat pendingIcon;
  QSet<int> pending;
  QTextCharFormat executableName;
  QSet<int> executable;
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
    const int line = currentBlock().blockNumber();
    const bool isPending = pending.contains(line), isExecutable = executable.contains(line);
    auto* colored = dynamic_cast<ColoredAs*>(currentBlockUserData());
    if (!colored && (isPending || isExecutable)) {
      colored = new ColoredAs;
      setCurrentBlockUserData(colored);
    }
    if (colored) {
      colored->pending = isPending;
      colored->executable = isExecutable;
    }
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
    // A file's name, after the dirs it's in.
    const qsizetype name = std::max(start, slash + 1);
    if (isExecutable)
      setFormat(name, text.size() - name, executableName);
  }
};

// The document of a TextEdit's `textDocument` (a QQuickTextDocument), if
// it's one.
QTextDocument*
documentOf(QObject* textDocument)
{
  auto* quickDocument = qobject_cast<QQuickTextDocument*>(textDocument);
  return quickDocument ? quickDocument->textDocument() : nullptr;
}

// Koil's T of a TextEdit's document (a QQuickTextDocument), if it has one.
// Koil's classes have no Q_OBJECT (so no moc), so it's found by its name
// (T::name) rather than by type.
template<class T>
T*
childOf(QObject* textDocument)
{
  auto* document = documentOf(textDocument);
  if (!document)
    return nullptr;
  return static_cast<T*>(document->findChild<QObject*>(T::name, Qt::FindDirectChildrenOnly));
}

// The highlighter T of a TextEdit's document, if it has one, or else a new
// one if `create` is set.
template<class T>
T*
highlighterOf(QObject* textDocument, bool create)
{
  auto* highlighter = childOf<T>(textDocument);
  auto* document = documentOf(textDocument);
  if (!highlighter && create && document) {
    highlighter = new T(document);
    highlighter->setObjectName(T::name);
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

// The colors in `keysAndColors`, which alternates keys and their colors, by
// key.
QHash<QString, QTextCharFormat>
colorsByKey(const QStringList& keysAndColors)
{
  QHash<QString, QTextCharFormat> colors;
  for (qsizetype i = 0; i + 1 < keysAndColors.size(); i += 2)
    colors.insert(keysAndColors.at(i), colored(keysAndColors.at(i + 1)));
  return colors;
}

// See setKeywordColors.
class KeywordHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  static inline const QString name = QStringLiteral("koilKeywordHighlighter");

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

// See setSpanColors.
class SpanHighlighter : public QSyntaxHighlighter
{
public:
  using QSyntaxHighlighter::QSyntaxHighlighter;

  static inline const QString name = QStringLiteral("koilSpanHighlighter");

  struct Span
  {
    int start;
    int length;
    QTextCharFormat format;
  };
  // By line.
  QHash<int, QList<Span>> spans;

protected:
  void highlightBlock(const QString&) override
  {
    for (const auto& span : spans.value(currentBlock().blockNumber()))
      setFormat(span.start, span.length, span.format);
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
// colors, or the layout it's laid out by (see setLineFormat). So the text
// isn't colored again (see TextColors), nor taken as changed (see
// TextChanges).
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

// While it lives, `document` isn't laid out (unless not `paused`), and then
// it's laid out once: Qt lays it out after each change otherwise.
class LayoutPaused
{
public:
  explicit LayoutPaused(QTextDocument* document, bool paused = true)
    : document(paused ? document : nullptr)
  {
    if (this->document)
      this->document->setLayoutEnabled(false);
  }
  ~LayoutPaused()
  {
    if (document)
      document->setLayoutEnabled(true);
  }

private:
  QTextDocument* document;
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
    setObjectName(name);
    connect(document, &QTextDocument::contentsChange, this, [this](int from, int, int added) {
      if (!formatOnly(this->document()))
        color(from, from + added);
    });
  }

  static inline const QString name = QStringLiteral("koilTextColors");

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
    const LayoutPaused paused(doc);
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
  const LayoutPaused paused(document, !lines || lines->size() > 20);
  if (lines) {
    QTextCursor cursor(document);
    cursor.beginEditBlock();
    for (const int line : *lines)
      highlighter->rehighlightBlock(document->findBlockByNumber(line));
    cursor.endEditBlock();
  } else {
    highlighter->rehighlight();
  }
}

// A TextEdit with more characters than this builds only the lines in view
// (QQuickTextEditPrivate::largeTextSizeThreshold).
constexpr qsizetype largeTextSize = 10000;

// The code point at `i` of `text`, and the one before it.
char32_t
codePointAt(QStringView text, qsizetype i)
{
  const QChar c = text.at(i);
  if (c.isHighSurrogate() && i + 1 < text.size() && text.at(i + 1).isLowSurrogate())
    return QChar::surrogateToUcs4(c, text.at(i + 1));
  return c.unicode();
}

char32_t
codePointBefore(QStringView text, qsizetype i)
{
  const QChar c = text.at(i - 1);
  if (c.isLowSurrogate() && i >= 2 && text.at(i - 2).isHighSurrogate())
    return QChar::surrogateToUcs4(text.at(i - 2), c);
  return c.unicode();
}

// A space a row can end after: not a no-break one.
bool
isBlank(char32_t c)
{
  return QChar::isSpace(c) && c != 0xa0 && c != 0x2007 && c != 0x202f;
}

// A character of a word: a letter or a digit (not `_`, as a regex's \w
// has it, so `snake_case` breaks after its `_`s).
bool
isWord(char32_t c)
{
  return QChar::isLetterOrNumber(c) || QChar::isMark(c);
}

// What ends something (a `,`, a `.`, a closing bracket or quote) or joins
// two words (a `-`, a `_`, a `/`), which stays with the word before it.
bool
staysBefore(char32_t c)
{
  switch (QChar::category(c)) {
    case QChar::Punctuation_Close:
    case QChar::Punctuation_FinalQuote:
      return true;
    default:
      return c < 0x80 && QStringView(u",.;:!?%'\"-_/").contains(QChar(c));
  }
}

// Whether a row may end before the character at `i` of `text`, so that it
// starts the next one: after a space, or where a word starts or ends, as a
// regex's \b does (but at a `_` too), not before a space (which ends the
// row it's on), nor before what stays with the word before it (see
// staysBefore).
bool
breaksBefore(QStringView text, qsizetype i)
{
  const char32_t c = codePointAt(text, i), before = codePointBefore(text, i);
  if (isBlank(c))
    return false;
  if (isBlank(before))
    return true;
  return isWord(before) != isWord(c) && !staysBefore(c);
}

// Where the name starts on a line of the listing, after its prefix: an
// icon (one character) and two spaces, or three spaces (see Prefixes in
// Vim.qml). 0 if it has none.
qsizetype
prefixEnd(QStringView text)
{
  if (text.isEmpty())
    return 0;
  const qsizetype icon = text.at(0).isHighSurrogate() && text.size() > 1 ? 2 : 1;
  return text.mid(icon).startsWith(u"  ") ? icon + 2 : 0;
}

// How many rows each line of a document takes, by line number, with how
// many come before a line, found in O(log n) (a Fenwick tree, `tree`): the
// layout gives a line's place each time Qt asks, many times a frame, and an
// edit changes the counts of its own lines only. A line has a row at least.
class RowCounts
{
public:
  int size() const { return int(counts.size()); }
  qint64 total() const { return sum; }
  int at(int line) const { return counts.at(line); }

  void reset(std::vector<int> all)
  {
    counts = std::move(all);
    rebuild();
  }

  // Replaces the counts of `removed` lines from `line` with `added`.
  void replace(int line, int removed, const std::vector<int>& added)
  {
    if (removed == int(added.size())) {
      for (int i = 0; i < removed; ++i)
        set(line + i, added.at(i));
      return;
    }
    counts.erase(counts.begin() + line, counts.begin() + line + removed);
    counts.insert(counts.begin() + line, added.begin(), added.end());
    rebuild();
  }

  // The rows of the lines before `line`.
  qint64 before(int line) const
  {
    qint64 rows = 0;
    for (int i = line; i > 0; i -= i & -i)
      rows += tree.at(i);
    return rows;
  }

  // The line row `row` is on (the last one, past the end).
  int lineAt(qint64 row) const
  {
    int line = 0;
    int step = 1;
    while (step * 2 <= size())
      step *= 2;
    for (; step; step /= 2) {
      if (line + step <= size() && tree.at(line + step) <= row) {
        line += step;
        row -= tree.at(line);
      }
    }
    return qBound(0, line, size() - 1);
  }

private:
  void set(int line, int rows)
  {
    const int change = rows - counts.at(line);
    if (!change)
      return;
    counts.at(line) = rows;
    sum += change;
    for (int i = line + 1; i <= size(); i += i & -i)
      tree.at(i) += change;
  }

  void rebuild()
  {
    tree.assign(counts.size() + 1, 0);
    sum = 0;
    for (int i = 1; i <= size(); ++i) {
      tree.at(i) += counts.at(i - 1);
      sum += counts.at(i - 1);
      if (const int up = i + (i & -i); up <= size())
        tree.at(up) += tree.at(i);
    }
  }

  std::vector<int> counts;
  std::vector<qint64> tree;
  qint64 sum = 0;
};

class TextLayout;

// A line too long for Qt (see TextLayout), as its block's user data, which
// Qt deletes with the block: its length, which the layout keeps the longest
// of.
struct LongLine : QTextBlockUserData
{
  explicit LongLine(TextLayout* layout);
  ~LongLine() override;

  TextLayout* layout;
  int length = 0;
};

// Koil's layout of a TextEdit's document, in place of Qt's (see
// setLineFormat). Every line's rows are on a grid of rows `lineHeight`
// tall, with the text's baseline `baseline` down each, however tall its
// characters are (an emoji's font is taller), or if `lineHeight` is 0, as
// tall as the font's lines, as Qt's are (see rowHeight). While lines wrap, a row ends
// where breaksBefore lets it, the last place that fits, or else where the
// next character doesn't fit; in the listing (`prefixed`), not in a line's
// prefix nor right after it, which would leave its icon alone, and the rows
// after a line's first start under its name (see indent). None reaches
// into the `rightMargin`. A line longer than `longLength` is hidden from Qt
// (QTextBlock::setVisible), which neither lays it out nor draws it (a
// megabyte took seconds, and as long for each edit): it's given its rows
// here, `rowLength` characters a row while lines wrap, and Koil draws what's
// in view of it (see longLineRuns). Qt's own layout can do none of this: its
// rows break where Unicode's line breaking says, it places a line by its
// characters' heights, and it gives a hidden line no room, so the lines
// after hidden ones had to be given margins as tall as their rows.
class TextLayout : public QAbstractTextDocumentLayout
{
public:
  TextLayout(QTextDocument* document, QQuickItem* textEdit)
    : QAbstractTextDocumentLayout(document)
    , textEdit(textEdit)
  {
    setObjectName(name);
    // Told before each change to the text, but not before one to what it's
    // laid out by (see documentChanged).
    connect(document, &QTextDocument::contentsChange, this, [this] { textChanged = true; });
  }

  ~TextLayout() override
  {
    for (auto* line : std::as_const(longLines))
      line->layout = nullptr;
  }

  static inline const QString name = QStringLiteral("koilTextLayout");

  double lineHeight = 1;
  double baseline = 0;
  double rightMargin = 0;
  bool prefixed = false;
  int longLength = largeTextSize;
  QSet<LongLine*> longLines;

  // Takes a new grid (see setLineFormat), and lays the text out again as
  // far as it changes it.
  void setFormat(double height, double base, double margin, bool listing, int longAt)
  {
    const bool rows = rightMargin != margin || prefixed != listing;
    const bool moved = lineHeight != height || baseline != base;
    const bool hiding = longLength != longAt;
    if (!rows && !moved && !hiding)
      return;
    lineHeight = height;
    baseline = base;
    rightMargin = margin;
    prefixed = listing;
    longLength = longAt;
    if (!canLayout()) {
      stale = true;
      return;
    }
    // A line's rows depend on these only while lines wrap.
    if (hiding || (rows && wrapping()))
      layoutAll();
    else
      placeAll();
    // The TextEdit hears of no change to the text, so its size, its lines
    // (drawn again where they are now) and its cursor's place are told
    // here, through slots of Qt's that aren't public.
    for (const char* slot : { "updateSize", "updateWholeDocument", "moveCursorDelegate" })
      QMetaObject::invokeMethod(textEdit, slot);
  }

  // How tall a row is, and how far down it its baseline is: as the grid
  // was given, else the font's line spacing and ascent, as Qt lays out a
  // line (not lineSpacing itself: Qt rounds a line's height up).
  qreal rowHeight() const
  {
    return lineHeight > 0 ? lineHeight
                          : std::ceil(QFontMetricsF(document()->defaultFont()).lineSpacing());
  }

  qreal rowBaseline() const
  {
    return lineHeight > 0 ? baseline : QFontMetricsF(document()->defaultFont()).ascent();
  }

  // How wide a column is: every character of the font advances one (see
  // Icon font in CLAUDE.md), as far as a hidden line goes.
  qreal charWidth() const
  {
    return qMax<qreal>(1, QFontMetricsF(document()->defaultFont()).horizontalAdvance(u' '));
  }

  // How much further right the rows a line wraps to start: in the listing,
  // under a name rather than its icon, past the prefix (three columns).
  qreal indent() const { return prefixed ? 3 * charWidth() : 0; }

  // Whether lines wrap: not without a width, which a TextEdit gives none
  // while it measures how wide its text is unwrapped.
  bool wrapping() const
  {
    const auto mode = document()->defaultTextOption().wrapMode();
    return mode != QTextOption::NoWrap && mode != QTextOption::ManualWrap &&
           document()->textWidth() >= 0;
  }

  // How many characters a row of a hidden line has while lines wrap (as
  // many as fit), else 0.
  int rowLength() const
  {
    if (!wrapping())
      return 0;
    return qMax(1, int(std::floor((textWidth() - rightMargin) / charWidth())));
  }

  int rowsOf(const QTextBlock& block) const { return rows.at(block.blockNumber()); }
  qint64 rowOf(const QTextBlock& block) const { return rows.before(block.blockNumber()); }

  // The block row `row` is in (the last one, past the end).
  QTextBlock blockAtRow(qint64 row) const
  {
    return rows.size() ? document()->findBlockByNumber(rows.lineAt(row)) : QTextBlock();
  }

  // How wide the widest line Qt lays out is, unwrapped, wrapped or not.
  qreal width() const { return widest; }

  int longest() const
  {
    int n = 0;
    for (const auto* line : std::as_const(longLines))
      n = qMax(n, line->length);
    return n;
  }

  // The position closest to `column` (a UTF-16 index) in row `row` of
  // `block`, a hidden line.
  int positionInRow(const QTextBlock& block, int row, double column) const
  {
    const int length = block.length() - 1, n = rowLength();
    const int rowCount = rowsOf(block);
    int from = 0, to = length;
    if (n) {
      row = qBound(0, row, rowCount - 1);
      from = row * n;
      // Not past a row's last character but in the last row: the position
      // after it is the next row's.
      to = row == rowCount - 1 ? length : from + n - 1;
    }
    int position = block.position() + from + qBound(0, qRound(column), to - from);
    if (position > block.position() && document()->characterAt(position).isLowSurrogate())
      --position;
    return position;
  }

  void draw(QPainter* painter, const PaintContext& context) override
  {
    Q_UNUSED(context);
    for (QTextBlock block = document()->begin(); block.isValid(); block = block.next()) {
      if (block.isVisible())
        block.layout()->draw(painter, blockBoundingRect(block).topLeft());
    }
  }

  int hitTest(const QPointF& point, Qt::HitTestAccuracy accuracy) const override
  {
    Q_UNUSED(accuracy);
    if (!rows.size())
      return 0;
    const qreal margin = document()->documentMargin();
    const qint64 row =
      qBound<qint64>(0, qint64(std::floor((point.y() - margin) / rowHeight())), rows.total() - 1);
    const QTextBlock block = blockAtRow(row);
    const int r = int(row - rowOf(block));
    const qreal x = point.x() - margin;
    if (!block.isVisible())
      return positionInRow(block, r, x / charWidth());
    const QTextLayout* layout = block.layout();
    if (!layout->lineCount())
      return block.position();
    return block.position() + layout->lineAt(qMin(r, layout->lineCount() - 1)).xToCursor(x);
  }

  int pageCount() const override { return 1; }

  QSizeF documentSize() const override
  {
    const qreal margin = document()->documentMargin();
    const qreal width = wrapping() ? qMax<qreal>(0, textWidth()) : widest;
    return { width + 2 * margin, qreal(rows.total()) * rowHeight() + 2 * margin };
  }

  QRectF frameBoundingRect(QTextFrame* frame) const override
  {
    return frame == document()->rootFrame() ? QRectF(QPointF(), documentSize()) : QRectF();
  }

  // Also a hidden line's, where it is: Qt's is empty, so a TextEdit put
  // the lines it draws after one in the wrong place as they moved (it moves
  // what it drew by how much the first line of it moved).
  QRectF blockBoundingRect(const QTextBlock& block) const override
  {
    const int line = block.blockNumber();
    if (!block.isValid() || line >= rows.size())
      return {};
    const qreal margin = document()->documentMargin();
    return { margin,
             margin + qreal(rows.before(line)) * rowHeight(),
             documentSize().width() - 2 * margin,
             rows.at(line) * rowHeight() };
  }

protected:
  // Qt's QTextDocument calls this with the part of the text that changed
  // (an edit, or new colors: what a highlighter colors while an edit is
  // told is in the edit's part), after it tells the change (contentsChange),
  // and with (0, 0, its length) when what the text is laid out by changes
  // (its width, font or wrap mode, or the layout is enabled again), which it
  // doesn't tell: so a resize while lines don't wrap lays out nothing. Also
  // while the layout is disabled (setLayoutEnabled), when it waits.
  void documentChanged(int from, int removed, int added) override
  {
    const bool told = std::exchange(textChanged, false);
    auto* doc = document();
    // Made now, in this thread, if clearing the text deleted it: Qt Quick
    // asks for it as it draws, in its render thread (where a QObject of the
    // document can't be made), and Qt's layout asked first.
    doc->rootFrame();
    if (!canLayout()) {
      stale = true;
      return;
    }
    const Settings now = settings();
    if (!told && from == 0 && removed == 0 && added == doc->characterCount()) {
      if (stale || !rows.size() || now.relayoutsAfter(laidOutBy))
        layoutAll();
      laidOutBy = now;
      return;
    }
    if (stale || now.relayoutsAfter(laidOutBy)) {
      layoutAll();
      laidOutBy = now;
      return;
    }
    const QTextBlock first = doc->findBlock(qMin(from, doc->characterCount() - 1));
    const QTextBlock last = doc->findBlock(qMin(from + added, doc->characterCount() - 1));
    if (!first.isValid() || !last.isValid()) {
      layoutAll();
      return;
    }
    const int line = first.blockNumber(), count = last.blockNumber() - line + 1;
    // The lines that were where these are.
    const int was = count - (doc->blockCount() - rows.size());
    if (was < 1 || line + was > rows.size()) {
      layoutAll();
      return;
    }
    std::vector<int> counts;
    std::vector<qreal> widths;
    counts.reserve(count);
    widths.reserve(count);
    for (QTextBlock block = first;; block = block.next()) {
      const auto [blockRows, blockWidth] = layoutBlock(block);
      counts.push_back(blockRows);
      widths.push_back(blockWidth);
      if (block == last)
        break;
    }
    rows.replace(line, was, counts);
    // The widest line again, from all of them only if it was one of these.
    bool wasWidest = false;
    for (int i = line; i < line + was; ++i)
      wasWidest = wasWidest || lineWidths.at(i) >= widest;
    lineWidths.erase(lineWidths.begin() + line, lineWidths.begin() + line + was);
    lineWidths.insert(lineWidths.begin() + line, widths.begin(), widths.end());
    const qreal widestHere = widths.empty() ? 0 : *std::max_element(widths.begin(), widths.end());
    if (wasWidest && widestHere < widest)
      widest = lineWidths.empty() ? 0 : *std::max_element(lineWidths.begin(), lineWidths.end());
    else
      widest = qMax(widest, widestHere);
  }

private:
  // What the text is laid out by, other than this layout's own grid.
  struct Settings
  {
    QFont font;
    bool wrap = false;
    qreal width = 0;
    qreal tabs = 0;
    bool designMetrics = false;

    // Whether text laid out by `was` must be laid out again: the width
    // matters only while lines wrap.
    bool relayoutsAfter(const Settings& was) const
    {
      return font != was.font || wrap != was.wrap || tabs != was.tabs ||
             designMetrics != was.designMetrics || (wrap && width != was.width);
    }
  };

  Settings settings() const
  {
    const auto option = document()->defaultTextOption();
    return { document()->defaultFont(),
             wrapping(),
             textWidth(),
             option.tabStopDistance(),
             option.useDesignMetrics() };
  }

  bool canLayout() const
  {
    return document()->isLayoutEnabled() && !document()->pageSize().isNull();
  }

  qreal textWidth() const { return document()->textWidth() - 2 * document()->documentMargin(); }

  void layoutAll()
  {
    std::vector<int> counts;
    lineWidths.clear();
    counts.reserve(document()->blockCount());
    lineWidths.reserve(document()->blockCount());
    widest = 0;
    for (QTextBlock block = document()->begin(); block.isValid(); block = block.next()) {
      const auto [blockRows, blockWidth] = layoutBlock(block);
      counts.push_back(blockRows);
      lineWidths.push_back(blockWidth);
      widest = qMax(widest, blockWidth);
    }
    rows.reset(std::move(counts));
    stale = false;
    laidOutBy = settings();
  }

  // Puts the rows of the lines Qt lays out on the grid as it is now.
  void placeAll()
  {
    const Grid grid = this->grid();
    for (QTextBlock block = document()->begin(); block.isValid(); block = block.next()) {
      auto* layout = block.layout();
      if (!block.isVisible())
        continue;
      for (int i = 0; i < layout->lineCount(); ++i)
        place(layout->lineAt(i), i, grid);
    }
  }

  // Where a row goes: its height, its baseline, and how far right the rows
  // after a line's first start.
  struct Grid
  {
    qreal height;
    qreal baseline;
    qreal indent;
  };

  Grid grid() const { return { rowHeight(), rowBaseline(), indent() }; }

  static void place(QTextLine line, int row, const Grid& grid)
  {
    line.setPosition(
      QPointF(row ? grid.indent : 0, row * grid.height + grid.baseline - line.ascent()));
  }

  // Lays out a line (a block), or hides it from Qt if it's too long, and
  // gives how many rows it takes and how wide it is.
  std::pair<int, qreal> layoutBlock(QTextBlock block)
  {
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
    auto* layout = block.layout();
    if (isLong) {
      layout->clearLayout();
      const int n = rowLength();
      return { n ? qMax(1, (length + n - 1) / n) : 1, 0 };
    }
    const bool wrap = wrapping();
    QTextOption option = document()->defaultTextOption();
    option.setWrapMode(wrap ? QTextOption::WrapAnywhere : QTextOption::NoWrap);
    option.setTextDirection(block.textDirection());
    layout->setTextOption(option);
    // As the layout has it: with what an input method is typing.
    QString text = block.text();
    if (layout->preeditAreaPosition() >= 0)
      text.insert(layout->preeditAreaPosition(), layout->preeditAreaText());
    const qsizetype after = prefixed ? prefixEnd(text) : 0;
    const qreal room = textWidth() - rightMargin, column = charWidth();
    const Grid grid = this->grid();
    int row = 0;
    // How wide the line is unwrapped: its rows' text side by side.
    qreal width = 0;
    layout->beginLayout();
    for (;; ++row) {
      QTextLine textLine = layout->createLine();
      if (!textLine.isValid())
        break;
      const qreal rowWidth = qMax(room - (row ? grid.indent : 0), column);
      textLine.setLineWidth(rowWidth);
      if (wrap)
        breakRow(layout, textLine, text, after, rowWidth);
      place(textLine, row, grid);
      width += textLine.horizontalAdvance();
      // Qt's advance leaves out the spaces a row ends with, which the line
      // unwrapped has between its words: a box sized to it wrapped there
      // again, a space too narrow.
      const int end = textLine.textStart() + textLine.textLength();
      int spaces = end;
      while (spaces > textLine.textStart() && text.at(spaces - 1).isSpace())
        --spaces;
      if (end < text.size() && spaces < end)
        width += QFontMetricsF(document()->defaultFont()).horizontalAdvance(text.mid(spaces, end - spaces));
    }
    layout->endLayout();
    return { qMax(1, row), width };
  }

  // Ends `line`, laid out to break anywhere, where breaksBefore lets it
  // (the last place in it), not before `after` (a listing line's prefix):
  // else it breaks where the next character doesn't fit. It's laid out
  // again as wide as up to that place, and halfway into the character
  // after it, which then doesn't fit.
  static void breakRow(QTextLayout* layout,
                       QTextLine& line,
                       QStringView text,
                       qsizetype after,
                       qreal rowWidth)
  {
    const int start = line.textStart(), end = start + line.textLength();
    if (end >= text.size())
      return; // the last row
    int at = end;
    while (at > start && at > after &&
           !(layout->isValidCursorPosition(at) && breaksBefore(text, at)))
      --at;
    if (at == end || at <= start || at <= after)
      return;
    const qreal x = line.cursorToX(at), next = line.cursorToX(layout->nextCursorPosition(at));
    line.setLineWidth((x + next) / 2);
    if (line.textStart() + line.textLength() != at)
      line.setLineWidth(rowWidth); // as it was, if that didn't end it there (right to left)
  }

  QQuickItem* textEdit;
  RowCounts rows;
  // How wide each line is, by number, and the widest of them.
  std::vector<qreal> lineWidths;
  qreal widest = 0;
  // Whether the text must be laid out again (the layout was disabled).
  bool stale = true;
  // Whether the document told of a change to the text since the last
  // documentChanged.
  bool textChanged = false;
  Settings laidOutBy;
};

LongLine::LongLine(TextLayout* layout)
  : layout(layout)
{
  layout->longLines.insert(this);
}

LongLine::~LongLine()
{
  if (layout)
    layout->longLines.remove(this);
}

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
    setObjectName(name);
    connect(document, &QTextDocument::contentsChange, this, &TextChanges::changed);
  }

  static inline const QString name = QStringLiteral("koilTextChanges");

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
useLineDeleteKey()
{
#ifdef Q_OS_MACOS
  auto* app = QCoreApplication::instance();
  app->installEventFilter(new LineDeleteFilter(app));
#endif
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
setLineFormat(QObject* textEdit,
              double lineHeight,
              double baseline,
              double rightMargin,
              bool listing,
              int longLength)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  auto* textDocument = item ? item->property("textDocument").value<QObject*>() : nullptr;
  auto* document = documentOf(textDocument);
  if (!document)
    return;
  if (auto* layout = childOf<TextLayout>(textDocument)) {
    layout->setFormat(lineHeight, baseline, rightMargin, listing, longLength);
    return;
  }
  auto* layout = new TextLayout(document, item);
  layout->lineHeight = lineHeight;
  layout->baseline = baseline;
  layout->rightMargin = rightMargin;
  layout->prefixed = listing;
  layout->longLength = longLength;
  {
    // Which Qt tells as a change to all the text, which it isn't.
    const FormatOnly formatting(document);
    document->setDocumentLayout(layout); // which deletes Qt's
  }
  for (const char* slot : { "updateSize", "updateWholeDocument" })
    QMetaObject::invokeMethod(item, slot);
}

double
layoutWidth(QObject* textDocument)
{
  auto* layout = childOf<TextLayout>(textDocument);
  return layout ? layout->width() : 0;
}

void
setText(QObject* textEdit, const QString& text)
{
  auto* item = qobject_cast<QQuickItem*>(textEdit);
  if (!item)
    return;
  auto* textDocument = item->property("textDocument").value<QObject*>();
  auto* document = documentOf(textDocument);
  if (!document)
    return;
  // The old text out and the new one in, in an edit block: the document
  // tells its layout and the TextEdit when it ends. Emptying the TextEdit
  // first (the way setting its text does) changed its width, as the scroll
  // bar went, and that laid out the new text again.
  // The new text is colored as it goes in, with the colors as they are now.
  if (auto* colors = childOf<TextColors>(textDocument))
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
  auto* document = textEdit ? documentOf(textEdit->property("textDocument").value<QObject*>())
                            : nullptr;
  if (!document)
    return;
  // As TextEdit's remove does, which is in bounds, and its insert, which a
  // cursor's insertText does after it removes the selection, in one edit
  // block. Both then update the cursor's rectangle only if the character
  // format there changed, which plain text's doesn't.
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

int
longestLine(QObject* textDocument)
{
  auto* layout = childOf<TextLayout>(textDocument);
  return layout ? layout->longest() : 0;
}

QString
longLineSpot(QObject* textDocument, int position)
{
  auto* layout = childOf<TextLayout>(textDocument);
  if (!layout || layout->longLines.isEmpty())
    return {};
  const QTextBlock block = layout->document()->findBlock(position);
  if (!block.isValid() || block.isVisible())
    return {};
  int column = position - block.position();
  qint64 row = layout->rowOf(block);
  if (const int n = layout->rowLength()) {
    // Where a row ends is where the next one starts, but at the line's end.
    int rows = column / n;
    if (rows && rows * n == column && column == block.length() - 1)
      --rows;
    row += rows;
    column -= rows * n;
  }
  return QString::number(row) + u' ' + QString::number(column);
}

int
longLinePosition(QObject* textDocument, int row, double column)
{
  auto* layout = childOf<TextLayout>(textDocument);
  if (!layout || layout->longLines.isEmpty() || row < 0)
    return -1;
  const QTextBlock block = layout->blockAtRow(row);
  if (!block.isValid() || block.isVisible())
    return -1;
  const qint64 first = layout->rowOf(block);
  if (row >= first + layout->rowsOf(block))
    return -1;
  return layout->positionInRow(block, int(row - first), column);
}

QString
longLineRuns(QObject* textDocument, int firstRow, int lastRow, int firstColumn, int lastColumn)
{
  QJsonArray runs;
  auto* layout = childOf<TextLayout>(textDocument);
  if (!layout || layout->longLines.isEmpty())
    return QStringLiteral("[]");
  auto* doc = layout->document();
  const int rowLength = layout->rowLength();
  QTextBlock block = layout->blockAtRow(qMax(0, firstRow));
  for (qint64 row = layout->rowOf(block); block.isValid() && row <= lastRow; block = block.next()) {
    const int rows = layout->rowsOf(block);
    if (!block.isVisible()) {
      const int position = block.position(), length = block.length() - 1;
      // The highlighter's colors, in order.
      const auto formats = block.layout()->formats();
      for (qint64 r = qMax<qint64>(0, firstRow - row); r < rows && row + r <= lastRow; ++r) {
        const int rowStart = int(r) * rowLength;
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
  auto* document = documentOf(textDocument);
  if (document && !childOf<TextChanges>(textDocument))
    new TextChanges(document);
}

QStringList
takeTextChange(QObject* textDocument, bool withText)
{
  auto* changes = childOf<TextChanges>(textDocument);
  return changes ? changes->take(withText) : QStringList();
}

void
scrollToCursorInQml(QObject* textArea)
{
  // Qt's TextArea scrolls its Flickable to show its cursor rectangle (in a
  // private slot of its own), which is at the line's start in a line it
  // doesn't lay out (see TextLayout), however far into it the cursor is.
  if (textArea)
    QObject::disconnect(textArea, SIGNAL(cursorRectangleChanged()), textArea, nullptr);
}

void
setListingColors(QObject* textDocument,
                 const QStringList& iconColors,
                 const QString& pendingIconColor,
                 const QString& executableColor,
                 const QString& directoryColor)
{
  auto* highlighter = highlighterOf<ListingHighlighter>(textDocument, !directoryColor.isEmpty());
  if (!highlighter)
    return;
  if (directoryColor.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  const auto icons = colorsByKey(iconColors);
  const auto pendingIcon = colored(pendingIconColor);
  const auto executableName = colored(executableColor);
  const auto directory = colored(directoryColor);
  if (icons == highlighter->icons && pendingIcon == highlighter->pendingIcon &&
      executableName == highlighter->executableName && directory == highlighter->directory)
    return;
  highlighter->icons = icons;
  highlighter->pendingIcon = pendingIcon;
  highlighter->executableName = executableName;
  highlighter->directory = directory;
  recolor(highlighter);
}

void
setEntryLines(QObject* textDocument, const QStringList& pendingLines, const QStringList& executableLines)
{
  auto* highlighter = highlighterOf<ListingHighlighter>(textDocument, false);
  if (!highlighter || highlighter->isPath)
    return;
  const auto numbers = [](const QStringList& lines) {
    QSet<int> set;
    for (const auto& line : lines)
      set.insert(line.toInt());
    return set;
  };
  const auto pending = numbers(pendingLines), executable = numbers(executableLines);
  // The lines colored otherwise than they're pending (or run) now: not
  // only those that were, as Qt colors a line as an edit reaches it, with
  // the lines it has then, and vim's edit is a remove and an insert,
  // between which lines are other numbers (a :s's preview, a few lines
  // longer at each key, left a file's icon white).
  highlighter->pending = pending;
  highlighter->executable = executable;
  QSet<int> changed;
  for (auto block = highlighter->document()->begin(); block.isValid(); block = block.next()) {
    const auto* colored = dynamic_cast<ColoredAs*>(block.userData());
    const int line = block.blockNumber();
    if ((colored && colored->pending) != pending.contains(line) ||
        (colored && colored->executable) != executable.contains(line))
      changed.insert(line);
  }
  if (!changed.isEmpty())
    recolor(highlighter, changed);
}

void
setPathColors(QObject* textDocument, const QString& directoryColor, const QStringList& spans)
{
  auto* highlighter = highlighterOf<ListingHighlighter>(textDocument, true);
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
  auto* highlighter = highlighterOf<KeywordHighlighter>(textDocument, !keywordColors.isEmpty());
  if (!highlighter)
    return;
  if (keywordColors.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  const auto keywords = colorsByKey(keywordColors);
  if (keywords == highlighter->keywords)
    return;
  highlighter->keywords = keywords;
  recolor(highlighter);
}

void
setSpanColors(QObject* textDocument, const QStringList& spans)
{
  auto* highlighter = highlighterOf<SpanHighlighter>(textDocument, !spans.isEmpty());
  if (!highlighter)
    return;
  if (spans.isEmpty()) {
    delete highlighter; // which takes its colors away
    return;
  }
  highlighter->spans.clear();
  for (qsizetype i = 0; i + 3 < spans.size(); i += 4)
    highlighter->spans[spans.at(i).toInt()].append(
      { spans.at(i + 1).toInt(), spans.at(i + 2).toInt(), colored(spans.at(i + 3)) });
  recolor(highlighter);
}

void
setTextColors(QObject* textDocument, const QStringList& colors, const QString& fileName)
{
  auto* document = documentOf(textDocument);
  if (!document)
    return;
  auto* textColors = childOf<TextColors>(textDocument);
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
    textColors = new TextColors(document);
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
