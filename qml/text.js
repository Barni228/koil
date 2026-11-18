.pragma library

// Text helpers, shared by Vim.qml and the views. `t` is the whole text and
// positions are UTF-16 indexes into it, as in the editor. None of these
// keep any state, but for the line starts they found (see lineIndex).

// ---- Lines -----------------------------------------------------------------

// Where the lines of long texts start, as far as they were looked for, for
// the last two texts asked about (the listing's and the path field's,
// say): { text, starts, done }, where starts[k] is where line k + 1
// starts, and `done` says they're all there. Finding a line from the
// text's start took over a millisecond at 40,000 lines, and the status
// line, line numbers and highlights do it at every key. Shorter texts
// (yanked lines, say) are looked through each time instead, and keep the
// long ones in.
const indexedLength = 10000;
let lineIndexes = [];

// Whether a and b are the same string, not only the same text: Koil's
// System.sameString, given by compareStringsWith, as V4's `===` hashes all
// of two strings unless they're the same one (a second for a gigabyte,
// many times a key). Without Koil (the tests), `===`.
let sameString = (a, b) => a === b;

function compareStringsWith(f) {
    sameString = f;
}

function lineIndex(t) {
    const fresh = { text: t, starts: [0], done: false };
    if (t.length < indexedLength)
        return fresh;
    // The same string, not only the same text, which is looked through
    // again (comparing them took longer).
    const x = lineIndexes.find(x => x.text.length === t.length && sameString(x.text, t)) || fresh;
    x.text = t;
    lineIndexes = [x].concat(lineIndexes.filter(y => y !== x)).slice(0, 2);
    return x;
}

// `after` is `before` with [start, end) replaced by `text`: the line starts
// found in `before` go to `after`, moved past the edit, so a long text
// isn't looked through again after each edit (a gigabyte took a second).
function carryLines(before, after, start, end, text) {
    if (after.length < indexedLength)
        return;
    const x = lineIndexes.find(x => x.text.length === before.length && sameString(x.text, before));
    if (!x)
        return;
    const s = x.starts, d = text.length - (end - start);
    // Only as far as they were found, from where findLines goes on, so
    // none of the edit's if they weren't found as far as its start.
    if (!x.done && s[s.length - 1] <= start) {
        lineIndexes = [{ text: after, starts: s.slice(), done: false }, x];
        return;
    }
    // Those at the edit's start or before it stay, those past its end move,
    // and the line breaks it puts in start lines of their own.
    const lo = partition(0, s.length, i => s[i] <= start);
    const starts = s.slice(0, lo);
    for (let i = text.indexOf("\n"); i >= 0; i = text.indexOf("\n", i + 1))
        starts.push(start + i + 1);
    let k = lo;
    while (k < s.length && s[k] <= end)
        k++;
    const moved = s.slice(k).map(p => p + d);
    lineIndexes = [{ text: after, starts: starts.concat(moved), done: x.done }, x];
}

// The first index in [from, to) that `before` is false for, where it's true
// for those before it and false for those after (or `to`): a binary search,
// for sorted lists that can be long (line starts, hidden text, highlights).
function partition(from, to, before) {
    let lo = from, hi = to;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (before(mid))
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}

// Finds line starts in x until it has `count` of them and one past p (or
// all of them).
function findLines(x, count, p) {
    const t = x.text, s = x.starts;
    while (!x.done && (s.length < count || s[s.length - 1] <= p)) {
        const i = t.indexOf("\n", s[s.length - 1]);
        if (i < 0)
            x.done = true;
        else
            s.push(i + 1);
    }
}

function lineStart(t, p) {
    return p <= 0 ? 0 : t.lastIndexOf("\n", p - 1) + 1;
}

function lineEnd(t, p) {
    const i = t.indexOf("\n", p);
    return i < 0 ? t.length : i;
}

// Where the line breaks in [from, to) of t are, in order.
function lineBreaks(t, from, to) {
    const r = [];
    for (let i = t.indexOf("\n", from); i >= 0 && i < to; i = t.indexOf("\n", i + 1))
        r.push(i);
    return r;
}

function isBlank(ch) {
    return ch === " " || ch === "\t";
}

function isEmptyLine(t, ls) {
    return ls >= t.length || t[ls] === "\n";
}

// Normal mode keeps the cursor on a character, never past the line's end.
function clampNormal(t, p) {
    p = Math.max(0, Math.min(p, t.length));
    const ls = lineStart(t, p), le = lineEnd(t, p);
    return charStart(t, le > ls && p >= le ? le - 1 : p);
}

function countLines(t) {
    const x = lineIndex(t);
    findLines(x, Infinity, -1);
    return x.starts.length;
}

// Lines covered by a linewise span, which ends after its last newline.
function spannedLines(s) {
    return countLines(s) - (s.endsWith("\n") ? 1 : 0);
}

// Where line `line` (from 1) starts, or the last line, past the end.
function lineToPos(t, line) {
    const x = lineIndex(t);
    findLines(x, line, -1);
    return x.starts[Math.max(0, Math.min(line, x.starts.length) - 1)];
}

// The line number (from 1) of position p.
function lineOf(t, p) {
    const x = lineIndex(t), s = x.starts;
    findLines(x, 0, p);
    // How many lines start at p or before it.
    return Math.max(1, partition(0, s.length, i => s[i] <= p));
}

// ---- Characters ------------------------------------------------------------

// A character is one code point plus the code points that attach to it:
// combining marks, variation selectors, emoji modifiers and tags, and
// whatever follows a zero-width joiner. Like Qt, vim moves over one as a
// whole, so the cursor never lands inside an emoji (or an icon hiding text).
function attaches(t, i) {
    const c = t.codePointAt(i);
    return c >= 0x300 && c <= 0x36F || c >= 0x1AB0 && c <= 0x1AFF || c >= 0x1DC0 && c <= 0x1DFF
        || c >= 0x20D0 && c <= 0x20FF || c >= 0xFE00 && c <= 0xFE0F || c >= 0xFE20 && c <= 0xFE2F
        || c === 0x200D || c >= 0x1F3FB && c <= 0x1F3FF || c >= 0xE0000 && c <= 0xE0FFF
        || t.charCodeAt(i - 1) === 0x200D;
}

// A code unit that may not be a character of its own, or may have the
// next one attach to it (see attaches): a surrogate, a zero-width joiner or
// a combining mark. Any other is a character of its own, so a line of only
// those has as many columns as code units, which `column` and `atColumn`
// count without going through it a character at a time (a long line took
// seconds).
const mayAttach = /[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u200d\u20d0-\u20ff\ud800-\udfff\ufe00-\ufe0f\ufe20-\ufe2f]/;

function isLowSurrogate(t, i) {
    const c = t.charCodeAt(i), h = t.charCodeAt(i - 1);
    return c >= 0xDC00 && c <= 0xDFFF && h >= 0xD800 && h <= 0xDBFF;
}

// Whether the character at i is in a Private Use Area, where Nerd Fonts
// put their icons.
function isPrivateUse(t, i) {
    const c = t.codePointAt(i);
    return c >= 0xE000 && c <= 0xF8FF || c >= 0xF0000 && c <= 0x10FFFD;
}

// End of the character at p.
function charEnd(t, p) {
    const n = t.length;
    if (p >= n)
        return n;
    if (t[p] === "\n")
        return p + 1;
    let q = p + 1;
    while (q < n && (isLowSurrogate(t, q) || t[q] !== "\n" && attaches(t, q)))
        q++;
    return q;
}

// Start of the character that p is in.
function charStart(t, p) {
    if (p >= t.length)
        return Math.max(p, 0);
    let q = p;
    while (q > 0 && t[q - 1] !== "\n" && (isLowSurrogate(t, q) || attaches(t, q)))
        q--;
    return q;
}

// Steps over up to `count` characters, but not past `limit`.
function advance(t, p, count, limit) {
    for (let i = 0; i < count && p < limit; i++)
        p = Math.min(charEnd(t, p), limit);
    return p;
}

function retreat(t, p, count, limit) {
    for (let i = 0; i < count && p > limit; i++)
        p = Math.max(charStart(t, p - 1), limit);
    return p;
}

// Column of p in its line, counted in characters.
function column(t, p) {
    // p can be past the end: the editor may report its cursor before the
    // text change that moved it.
    p = Math.min(p, t.length);
    const ls = lineStart(t, p), i = t.slice(ls, p).search(mayAttach);
    if (i < 0)
        return p - ls;
    // A character a code unit up to the first that may not be one.
    let q = charStart(t, ls + i), col = q - ls;
    for (; q < p; q = charEnd(t, q))
        col++;
    return col;
}

// How many columns t has from `from` to `to`, roughly: one per code point,
// so a surrogate pair is one, but an emoji made of several is several. For
// lining up what's drawn after lines (see inLine), over all of a long text,
// where `column` would be too slow.
function columns(t, from, to) {
    let n = 0;
    for (let q = from; q < to; q++) {
        if ((t.charCodeAt(q) & 0xfc00) !== 0xdc00)
            n++;
    }
    return n;
}

// Where to line up `cells` ({ own, width }: what's drawn after a line, each
// going at its `own` column, right after the line, unless it's put in line),
// so the most of them are, and still end by column `room` (where the view
// ends): one of their own columns, where each whose own column isn't past
// it goes, if it fits there (one whose own column it is is there anyway). A
// longer line's stays at its own, and so does one that would end past
// `room`. -1 for no cells.
function inLine(cells, room) {
    const sorted = cells.slice().sort((a, b) => a.own - b.own);
    // How many of the cells up to the column there are of each width.
    const widths = [];
    let best = -1, most = 0;
    for (let i = 0; i < sorted.length; ) {
        const column = sorted[i].own;
        // The ones whose own column it is, but don't fit.
        let fit = 0;
        for (; i < sorted.length && sorted[i].own === column; i++) {
            widths[sorted[i].width] = (widths[sorted[i].width] || 0) + 1;
            if (sorted[i].width > room - column)
                fit++;
        }
        for (let w = Math.min(room - column, widths.length - 1); w >= 0; w--)
            fit += widths[w] || 0;
        // The closer one, if as many fit.
        if (fit > most) {
            most = fit;
            best = column;
        }
    }
    return best;
}

// Where a cell `width` wide whose own column is `own` goes, with the cells
// lined up at `column` (see inLine), and the view ending at `room`.
function cellColumn(own, width, column, room) {
    return own <= column && column + width <= room ? column : own;
}

// Position of column `col` in the line starting at ls, or of the line's
// last character when it's shorter.
function atColumn(t, ls, col) {
    const le = lineEnd(t, ls);
    // A character a code unit (see mayAttach) as far as the column.
    if (t.slice(ls, Math.min(le, ls + col + 1)).search(mayAttach) < 0)
        return Math.max(ls, Math.min(ls + col, le - 1));
    let q = ls;
    for (let i = 0; i < col && charEnd(t, q) < le; i++)
        q = charEnd(t, q);
    return q;
}

// ---- Words, paragraphs and pairs -------------------------------------------

// 0 for blanks, 1 for punctuation, 2 for word characters (or any
// non-blank for WORD motions).
function charClass(ch, big) {
    if (ch === undefined)
        return 0;
    const c = ch.charCodeAt(0);
    if (c === 32 || c === 9 || c === 10 || c === 13)
        return 0;
    if (big)
        return 2;
    if (c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c === 95 || c >= 0xC0)
        return 2;
    return 1;
}

// charClass of t's code unit at i, but 0 (a blank) where `blank(i)`
// says, if it's given: an icon that's indentation (see Vim.qml's
// iconBlanks), to the word motions below.
function classAt(t, i, big, blank) {
    const c = charClass(t[i], big);
    return c !== 0 && blank && blank(i) ? 0 : c;
}

function nextWordStart(t, p, big, blank) {
    const n = t.length;
    if (p >= n)
        return n;
    const c = classAt(t, p, big, blank);
    if (c !== 0)
        while (p < n && classAt(t, p, big, blank) === c)
            p++;
    while (p < n) {
        if (t[p] === "\n") {
            p++;
            if (p < n && t[p] === "\n")
                return p; // an empty line counts as a word
            continue;
        }
        if (classAt(t, p, big, blank) !== 0)
            return p;
        p++;
    }
    return n;
}

function prevWordStart(t, p, big, blank) {
    let q = p - 1;
    while (q > 0 && classAt(t, q, big, blank) === 0) {
        if (t[q] === "\n" && t[q - 1] === "\n")
            return q;
        q--;
    }
    if (q <= 0)
        return 0;
    const c = classAt(t, q, big, blank);
    while (q > 0 && classAt(t, q - 1, big, blank) === c)
        q--;
    return q;
}

function wordEnd(t, p, big, blank) {
    const n = t.length;
    let q = charEnd(t, p);
    while (q < n && classAt(t, q, big, blank) === 0)
        q++;
    if (q >= n)
        return p;
    const c = classAt(t, q, big, blank);
    for (let e = charEnd(t, q); e < n && classAt(t, e, big, blank) === c; e = charEnd(t, q))
        q = e;
    return q;
}

function prevWordEnd(t, p, big, blank) {
    let q = p;
    const c = classAt(t, q, big, blank);
    if (c !== 0)
        while (q > 0 && classAt(t, q - 1, big, blank) === c)
            q--;
    q--;
    while (q > 0 && classAt(t, q, big, blank) === 0) {
        if (t[q] === "\n" && t[q - 1] === "\n")
            return q;
        q--;
    }
    return charStart(t, Math.max(q, 0));
}

function wordAt(t, p) {
    const le = lineEnd(t, p);
    let s = p;
    while (s < le && charClass(t[s], false) !== 2)
        s++;
    if (s >= le)
        return null;
    while (s > 0 && charClass(t[s - 1], false) === 2)
        s--;
    let e = s;
    while (e < t.length && charClass(t[e], false) === 2)
        e++;
    return { start: s, text: t.slice(s, e) };
}

function findChar(t, p, kind, ch, count, repeat) {
    const ls = lineStart(t, p), le = lineEnd(t, p);
    let q = p;
    if (kind === "f" || kind === "t") {
        for (let i = 0; i < count; i++) {
            // Repeating "t" skips a match right next to the cursor.
            const from = kind === "t" && repeat && i === 0 && t[q + 1] === ch ? q + 2 : q + 1;
            const idx = t.indexOf(ch, from);
            if (idx < 0 || idx >= le)
                return null;
            q = idx;
        }
        return { pos: kind === "t" ? charStart(t, q - 1) : q, type: "inclusive" };
    }
    for (let i = 0; i < count; i++) {
        const from = kind === "T" && repeat && i === 0 && t[q - 1] === ch ? q - 2 : q - 1;
        if (from < ls)
            return null;
        const idx = t.lastIndexOf(ch, from);
        if (idx < ls)
            return null;
        q = idx;
    }
    return { pos: kind === "T" ? charEnd(t, q) : q, type: "exclusive" };
}

function matchPair(t, p) {
    const pairs = "()[]{}";
    const le = lineEnd(t, p);
    let q = p;
    while (q < le && pairs.indexOf(t[q]) < 0)
        q++;
    if (q >= le)
        return null;
    const k = bracketMatch(t, q, 0, t.length - 1);
    return k < 0 ? null : { pos: k, type: "inclusive" };
}

// Where the bracket at p (one of `()[]{}`) is matched in [from, to], or
// -1.
function bracketMatch(t, p, from, to) {
    const pairs = "()[]{}", i = pairs.indexOf(t[p]);
    const open = pairs[i & ~1], close = pairs[i | 1], step = i % 2 === 0 ? 1 : -1;
    let depth = 0;
    for (let k = p; k >= from && k <= to; k += step) {
        if (t[k] === open)
            depth += step;
        else if (t[k] === close)
            depth -= step;
        if (depth === 0)
            return k;
    }
    return -1;
}

// The bracket at p and the one it matches, as [at, match], when both are
// in [from, to]; with `before` (insert mode), the one before p if there's
// none at it, as vim's matchparen does. Null if there's none. Unlike
// matchPair, it looks no further than [from, to] (what's in view).
function bracketPair(t, p, before, from, to) {
    const pairs = "()[]{}";
    let i = p < t.length ? pairs.indexOf(t[p]) : -1;
    if (i < 0 && before && p > 0) {
        p--;
        i = pairs.indexOf(t[p]);
    }
    if (i < 0 || p < from || p > to)
        return null;
    const k = bracketMatch(t, p, from, to);
    return k < 0 ? null : [p, k];
}

function nextParagraph(t, p) {
    const n = t.length;
    let q = lineStart(t, p);
    while (q < n && isEmptyLine(t, q))
        q++;
    while (q < n) {
        const le = lineEnd(t, q);
        if (le >= n)
            return n;
        q = le + 1;
        if (isEmptyLine(t, q))
            return q;
    }
    return n;
}

function prevParagraph(t, p) {
    let q = lineStart(t, p);
    while (q > 0 && isEmptyLine(t, q))
        q = lineStart(t, q - 1);
    while (q > 0) {
        q = lineStart(t, q - 1);
        if (isEmptyLine(t, q))
            return q;
    }
    return 0;
}

// ---- Text objects ----------------------------------------------------------
// Each returns { start, end, linewise } with `end` exclusive, or null.

function textObject(t, p, obj, count) {
    switch (obj.ch) {
    case "w":
    case "W":
        return wordObject(t, p, obj.around, obj.ch === "W");
    case "p":
        return paragraphObject(t, p, obj.around);
    case "\"":
    case "'":
    case "`":
        return quoteObject(t, p, obj.around, obj.ch);
    case "(":
    case ")":
    case "b":
        return blockObject(t, p, obj.around, "(", ")", count);
    case "[":
    case "]":
        return blockObject(t, p, obj.around, "[", "]", count);
    case "{":
    case "}":
    case "B":
        return blockObject(t, p, obj.around, "{", "}", count);
    case "t": {
        const r = tagPair(t, p, count);
        return r && (obj.around ? { start: r.o1, end: r.c2, linewise: false }
            : { start: r.o2, end: r.c1, linewise: false });
    }
    default:
        return blockObject(t, p, obj.around, "<", ">", count);
    }
}

function wordObject(t, p, around, big) {
    const ls = lineStart(t, p), le = lineEnd(t, p);
    if (p >= le)
        return { start: p, end: p, linewise: false };
    const c = charClass(t[p], big);
    const same = i => charClass(t[i], big) === c;
    let s = p, e = p + 1;
    while (s > ls && same(s - 1))
        s--;
    while (e < le && same(e))
        e++;
    if (around) {
        if (c !== 0) {
            let e2 = e;
            while (e2 < le && isBlank(t[e2]))
                e2++;
            if (e2 > e)
                e = e2;
            else
                while (s > ls && isBlank(t[s - 1]))
                    s--;
        } else if (e < le) {
            const c2 = charClass(t[e], big);
            while (e < le && charClass(t[e], big) === c2)
                e++;
        }
    }
    return { start: s, end: e, linewise: false };
}

function quoteObject(t, p, around, q) {
    const ls = lineStart(t, p), le = lineEnd(t, p);
    const quotes = [];
    for (let i = ls; i < le; i++)
        if (t[i] === q && (i === ls || t[i - 1] !== "\\"))
            quotes.push(i);
    let open = -1, close = -1;
    for (let k = 0; k + 1 < quotes.length; k += 2)
        if (p >= quotes[k] && p <= quotes[k + 1]) {
            open = quotes[k];
            close = quotes[k + 1];
            break;
        }
    if (open < 0)
        for (let k = 0; k + 1 < quotes.length; k += 2)
            if (quotes[k] > p) {
                open = quotes[k];
                close = quotes[k + 1];
                break;
            }
    if (open < 0)
        return null;
    if (!around)
        return { start: open + 1, end: close, linewise: false };
    let s = open, e = close + 1;
    let e2 = e;
    while (e2 < le && isBlank(t[e2]))
        e2++;
    if (e2 > e)
        e = e2;
    else
        while (s > ls && isBlank(t[s - 1]))
            s--;
    return { start: s, end: e, linewise: false };
}

function blockObject(t, p, around, open, close, count) {
    let o = t[p] === open ? p : -1;
    let from = p - 1;
    for (let i = 0; i < count; i++) {
        if (i > 0 || o < 0) {
            let depth = 0;
            o = -1;
            for (let k = from; k >= 0; k--) {
                if (t[k] === close) {
                    depth++;
                } else if (t[k] === open) {
                    if (depth === 0) {
                        o = k;
                        break;
                    }
                    depth--;
                }
            }
            if (o < 0)
                return null;
        }
        from = o - 1;
    }
    let c = -1, depth = 0;
    for (let k = o; k < t.length; k++) {
        if (t[k] === open)
            depth++;
        else if (t[k] === close && --depth === 0) {
            c = k;
            break;
        }
    }
    if (c < 0)
        return null;
    if (around)
        return { start: o, end: c + 1, linewise: false };
    // A block whose braces sit on their own lines is changed linewise.
    if (t[o + 1] === "\n") {
        const cls = lineStart(t, c);
        if (/^[ \t]*$/.test(t.slice(cls, c)) && cls > o + 2)
            return { start: o + 2, end: cls, linewise: true };
        return { start: o + 2, end: c, linewise: false };
    }
    return { start: o + 1, end: c, linewise: false };
}

// The `count`th pair of tags out from p (an HTML or XML element p is in,
// its tags too), as { o1, o2, c1, c2 }: [o1, o2) the opening tag, [c1, c2)
// the closing one. A closing tag pairs with the nearest open one of its
// name, leaving those between unpaired (`<br>`, an `<li>` with no
// `</li>`); a tag ending with `/>` has no pair. Null if there's none.
function tagPair(t, p, count) {
    const around = [];
    eachTagPair(t, (o, c, depth) => {
        // Pairs are nested or apart, so those p is in close innermost first.
        if (o.start <= p && p < c.end)
            around.push({ o1: o.start, o2: o.end, c1: c.start, c2: c.end });
        return around.length >= count || depth === 0 && c.start > p;
    });
    return around[count - 1] || null;
}

// A tag, as tagPair takes them: `<name …>`, `</name>`, or `<name …/>`.
const tagSource = "<(\\/?)([A-Za-z][^\\s\\/>]*)[^<>]*>";

// Calls fn(o, c, depth) for each pair of t's tags (see tagPair), in the
// order they close: o and c the opening and closing tags' { start, end },
// and depth how many are open around them. fn returning true stops it.
function eachTagPair(t, fn) {
    const re = new RegExp(tagSource, "g"), open = [];
    let m;
    while ((m = re.exec(t))) {
        const end = m.index + m[0].length;
        if (!m[1]) {
            if (m[0][m[0].length - 2] !== "/")
                open.push({ name: m[2], start: m.index, end: end });
            continue;
        }
        let k = open.length - 1;
        while (k >= 0 && open[k].name !== m[2])
            k--;
        if (k < 0)
            continue;
        const o = open[k];
        open.length = k;
        if (fn(o, { start: m.index, end: end }, k))
            return;
    }
}

function paragraphObject(t, p, around) {
    const n = t.length;
    const ls = lineStart(t, p);
    const empty = isEmptyLine(t, ls);
    const nextLine = q => {
        const le = lineEnd(t, q);
        return le + 1 < n ? le + 1 : -1;
    };
    let s = ls;
    while (s > 0 && isEmptyLine(t, lineStart(t, s - 1)) === empty)
        s = lineStart(t, s - 1);
    let e = ls;
    for (let q = nextLine(e); q >= 0 && isEmptyLine(t, q) === empty; q = nextLine(q))
        e = q;
    if (around) {
        let q = nextLine(e);
        if (q >= 0) {
            for (; q >= 0 && isEmptyLine(t, q) !== empty; q = nextLine(q))
                e = q;
        } else {
            while (s > 0 && isEmptyLine(t, lineStart(t, s - 1)) !== empty)
                s = lineStart(t, s - 1);
        }
    }
    return { start: s, end: Math.min(lineEnd(t, e) + 1, n), linewise: true };
}

// ---- Indent ----------------------------------------------------------------

// A level of indent in t: a tab if more of its lines (of the first 2000)
// start with one than with a space, else 2, 4 or 8 spaces, as a line most
// often goes in by from the one before it (not by others: a line lined up
// with something), if lines do twice or more (one may be a mistake, as
// in text to reindent), else 4.
function indentUnit(t) {
    let tabs = 0, spaces = 0, last = 0;
    const steps = {};
    for (let ls = 0, n = 0; ls < t.length && n < 2000; n++) {
        let le = t.indexOf("\n", ls);
        if (le < 0)
            le = t.length;
        let e = ls;
        while (e < le && isBlank(t[e]))
            e++;
        if (e < le) {
            if (t[ls] === "\t") {
                tabs++;
            } else if (e > ls) {
                spaces++;
                const step = e - ls - last;
                if (step === 2 || step === 4 || step === 8)
                    steps[step] = (steps[step] || 0) + 1;
            }
            last = t[ls] === "\t" ? 0 : e - ls;
        }
        ls = le + 1;
    }
    if (tabs > spaces)
        return "\t";
    let best = 4;
    for (const s in steps)
        if (steps[s] >= 2 && steps[s] > (steps[best] || 0))
            best = Number(s);
    return " ".repeat(best);
}

// The starts of t's tags that pair with another (see tagPair), in order:
// an opening one with a closing one of its name, so `List<String>` isn't
// taken for a tag. An array, not a Set: V4's takes time in proportion to
// its size for each add and lookup (40,000 adds took 2 s).
function pairedTags(t) {
    const paired = [];
    eachTagPair(t, (o, c) => {
        paired.push(o.start, c.start);
    });
    return paired.sort((a, b) => a - b);
}

// Reads t's lines for their brackets (( [ {) and tags, as `=` and `g=`
// go by them: not those in strings and comments (those syntax.rs
// colors), nor a tag with no closing tag of its name (see pairedTags). A
// /* */ or <!-- --> comment, and a """ or ''' string (which syntax.rs
// doesn't know), can go on to the lines after, so every line is read, in
// order from t's start. With `hashes`, a # first on a line or after a
// blank always starts a comment, as in Python, YAML and shell, not only
// before a blank or a sign. Gives a function of a line (from `first`,
// after its indent, to `le`, its end) that gives
//   tokens: its brackets and tags, as { kind, close, at, end }
//   inComment: the comment (or """ string) it starts in, or null
//   comment: the one it ends in, going on to the next line, or null, as
//     { close, indent }: the same on each of its lines, with the indent
//     the caller gives it (null at first)
//   codeStart: where its code starts: after the comment it starts in, if
//     that ends on it (else le), or `first`
//   codeEnd: where the comment or string it ends in starts, else le
function codeScanner(t, hashes) {
    // Whether a tag that pairs starts at i, which only goes on.
    const paired = t.indexOf("</") >= 0 ? pairedTags(t) : [];
    let next = 0;
    const pairedAt = i => {
        while (next < paired.length && paired[next] < i)
            next++;
        return paired[next] === i;
    };
    const tagAt = new RegExp(tagSource, "y");
    const isWordAt = i => i >= 0 && charClass(t[i], false) === 2;
    const blankOr = (i, signs) => i < 0 || isBlank(t[i]) || t[i] === "\n" || signs.includes(t[i]);
    // Whether the ' at i comes after a string's prefix, as in Python's
    // f'…' or rb'…', rather than in a word, as in it's (as syntax.rs's
    // after_prefix).
    const afterPrefix = i => {
        let start = i;
        while (start > 0 && /[A-Za-z]/.test(t[start - 1]) && i - start < 3)
            start--;
        return !isWordAt(start - 1) && /^(?:[rbfu]|rb|br|fr|rf)$/i.test(t.slice(start, i));
    };
    // Whether a \ escapes the character at i (an odd number of them before it).
    const escaped = i => {
        let n = 0;
        while (i - n - 1 >= 0 && t.charCodeAt(i - n - 1) === 92)
            n++;
        return n % 2 === 1;
    };
    const signs = /[\/<#"'`()[\]{}]/g;
    // Whether a // at i is a division (`range(n // 2)`), as syntax.rs
    // has it: its line goes on to close a bracket opened before it (on
    // the line, in `tokens`), counting brackets as they come.
    const divides = (i, le, tokens) => {
        let open = 0;
        for (const k of tokens)
            if ("([{".includes(k.kind))
                open = k.close ? Math.max(open - 1, 0) : open + 1;
        for (let j = i + 2, rest = 0; open > 0 && j < le; j++) {
            const b = "([{)]}".indexOf(t[j]);
            if (b >= 3 && rest-- === 0)
                return true;
            if (b >= 0 && b < 3)
                rest++;
        }
        return false;
    };
    let comment = null;
    return (first, le) => {
        const tokens = [], inComment = comment;
        let i = first, codeEnd = le;
        if (comment) {
            const end = t.indexOf(comment.close, first);
            if (end < 0 || end >= le) {
                i = le;
                codeEnd = first;
            } else {
                i = end + comment.close.length;
                comment = null;
            }
        }
        const codeStart = Math.min(i, le);
        while (i < le) {
            // To the next character that can start something.
            signs.lastIndex = i;
            const found = signs.exec(t);
            if (!found || found.index >= le)
                break;
            i = found.index;
            const c = found[0];
            if (c === "/" && t[i + 1] === "/" && blankOr(i - 1, ";{}") && !divides(i, le, tokens)) {
                codeEnd = i;
                break;
            }
            const close = c === "/" && t[i + 1] === "*" && blankOr(i - 1, "({[,;=") ? "*/"
                : t.startsWith("<!--", i) ? "-->"
                : (c === "\"" || c === "'") && t.startsWith(c + c + c, i) ? c + c + c : null;
            if (close) {
                const end = t.indexOf(close, i + (close === "*/" || close === "-->" ? 2 : 3));
                if (end < 0 || end >= le) {
                    comment = { close: close, indent: null };
                    codeEnd = i;
                    break;
                }
                i = end + close.length;
                continue;
            }
            if (c === "#" && blankOr(i - 1, "") && (hashes || i + 1 >= le || isBlank(t[i + 1])
                    || t[i + 1] === "!" && t[i + 2] !== "[" || "#-=*/~:+|".includes(t[i + 1]))) {
                codeEnd = i;
                break;
            }
            if ((c === "\"" || c === "`" || c === "'" && (!isWordAt(i - 1) || afterPrefix(i))) && t[i - 1] !== "\\") {
                // A string, if it ends on the line (a ' one at a ' no word
                // goes on from: not it's, nor &'a).
                let j = t.indexOf(c, i + 1);
                while (j >= 0 && j < le && c !== "`" && escaped(j))
                    j = t.indexOf(c, j + 1);
                if (j >= 0 && j < le && !(c === "'" && isWordAt(j + 1))) {
                    i = j + 1;
                    continue;
                }
            }
            const b = "([{)]}".indexOf(c);
            if (b >= 0) {
                tokens.push({ kind: "([{"[b % 3], close: b >= 3, at: i, end: i + 1 });
            } else if (c === "<" && pairedAt(i)) {
                tagAt.lastIndex = i;
                const m = tagAt.exec(t);
                tokens.push({ kind: "<" + m[2], close: m[1] === "/", at: i, end: i + m[0].length });
                i += m[0].length;
                continue;
            }
            i++;
        }
        return { tokens: tokens, inComment: inComment, comment: comment, codeStart: codeStart, codeEnd: codeEnd };
    };
}

// The indents `=` gives the lines in `spans` ({ from, to }: the starts of
// a span's first and last lines, in order), by the brackets (( [ {) and
// the tags around them, as vim's C-indenting does without knowing the
// language: a line in brackets goes `unit` deeper than the line they
// open on, one that starts by closing them as deep as that line, a blank
// line has none, and a line in no brackets keeps its own (a block of
// Python or YAML stays as it is). Brackets in strings and comments don't
// count (see codeScanner). In a /* */ comment, a line starting with *
// goes a space deeper than the comment's first line, and others stay. A
// line's indent starts where textStart(its start) says (after the
// listing's prefix). Gives the edits, as { start, end, text }, for the
// lines whose indent changes.
function reindent(t, spans, unit, textStart) {
    const scan = codeScanner(t, false);
    // The brackets and tags open, as { kind, indent, line, level }: the
    // indent of the line each opens on, and whether it's the first still
    // open of its line, which a level of indent is for.
    const stack = [], edits = [];
    const pop = kind => {
        for (let k = stack.length - 1; k >= 0; k--) {
            if (stack[k].kind === kind) {
                const e = stack[k];
                stack.length = k;
                return e;
            }
        }
        return null;
    };
    const last = spans[spans.length - 1].to;
    let s = 0;
    for (let ls = 0, line = 0; ls <= last; line++) {
        let le = t.indexOf("\n", ls);
        if (le < 0)
            le = t.length;
        while (s < spans.length && spans[s].to < ls)
            s++;
        const inRange = s < spans.length && spans[s].from <= ls;
        const ts = textStart(ls);
        let first = ts;
        while (first < le && isBlank(t[first]))
            first++;
        const old = t.slice(ts, first);
        const read = scan(first, le), tokens = read.tokens, inComment = read.inComment;
        // Its indent: as its opener's line, if it starts by closing (the
        // outermost it closes), else a level deeper than the line the
        // innermost level opened on.
        let indent = null, k = 0, popped = null;
        if (inComment) {
            indent = inComment.close === "*/" && inComment.indent !== null && t[first] === "*"
                ? inComment.indent + " " : null;
        } else {
            for (let at = first; k < tokens.length && tokens[k].close && tokens[k].at === at; k++) {
                popped = pop(tokens[k].kind) || popped;
                at = tokens[k].end;
                while (at < le && isBlank(t[at]))
                    at++;
            }
            if (popped) {
                indent = popped.indent;
            } else {
                for (let e = stack.length - 1; e >= 0 && indent === null; e--)
                    if (stack[e].level)
                        indent = stack[e].indent + unit;
            }
        }
        if (first >= le)
            indent = "";
        if (inRange && indent !== null && indent !== old)
            edits.push({ start: ts, end: first, text: indent });
        const now = inRange && indent !== null ? indent : old;
        if (read.comment && read.comment.indent === null)
            read.comment.indent = now;
        for (; k < tokens.length; k++) {
            if (tokens[k].close)
                pop(tokens[k].kind);
            else
                stack.push({ kind: tokens[k].kind, indent: now, line: line, level: false });
        }
        let lowest = -1;
        for (let e = stack.length - 1; e >= 0 && stack[e].line === line; e--)
            lowest = e;
        if (lowest >= 0)
            stack[lowest].level = true;
        ls = le + 1;
    }
    return edits;
}

// The indents `g=` gives the lines in `spans` (as reindent's), guessed
// from the lines around them, for Python and YAML, whose blocks only
// indents show (see Guessed indent). A line opens a level if it leaves a
// bracket or tag open (as = reads them, see codeScanner, with # always a
// comment) or ends with : or \ (but a : in brackets, a dict's key's). A
// span's first line (one alone, or a block put where it doesn't fit)
// goes where the line above it lets it: a level deeper if that opens one
// (under what follows a bracket on its line, if anything does), else at
// its level or at that of a line it's in, whichever it was nearest, or,
// after a list's item (`- a: 1`), at the item's text if it was that deep;
// alone, it also goes deep enough for the line below. The span's other
// lines keep their places among themselves, moved with the first, but
// for what can't be meant: a line not deeper than a bracket or \ above
// it goes deeper, as the first would; one a column deeper than a line
// that opens none goes back to it; and one shallower than the line
// above, out of brackets, goes at the nearest level. A line starting by closing a
// bracket goes as deep as the line that opened it (or as much deeper as
// it was, in the span), and the lines after it go by that line, as after
// one going on after a \. A line in a /* */ comment or a """ docstring
// moves with its first line, one in another """ string stays, a line of
// only a comment moves with the line above, and a blank one has no
// indent. A tab is 4 columns, as > has it. Gives the edits, as reindent
// does.
function guessIndents(t, spans, unit, textStart) {
    const step = unit === "\t" ? 4 : unit.length;
    const widthOf = (from, to) => {
        let w = 0;
        for (let i = from; i < to; i++)
            w += t[i] === "\t" ? 4 : 1;
        return w;
    };
    const indentOf = w => unit === "\t" ? "\t".repeat(Math.floor(w / 4)) + " ".repeat(w % 4) : " ".repeat(w);
    const firstOf = (ls, le) => {
        let i = textStart(ls);
        while (i < le && isBlank(t[i]))
            i++;
        return i;
    };
    // The width of the indent of the first line after le that isn't
    // blank, if it's after `span` (else -1).
    const below = (le, span) => {
        for (let q = le + 1; q < t.length; ) {
            let qe = t.indexOf("\n", q);
            if (qe < 0)
                qe = t.length;
            const f = firstOf(q, qe);
            if (f < qe)
                return q > span.to ? widthOf(textStart(q), f) : -1;
            q = qe + 1;
        }
        return -1;
    };
    const quoted = c => c.close === "\"\"\"" || c.close === "'''";
    const opens = l => l.kinds.length > 0 || l.ends === ":" || l.ends === "\\";
    const forces = l => l.kinds.length > 0 || l.ends === "\\";
    const item = /(?:[-*+]|\d{1,9}[.)])[ \t]+(?=[^ \t\n])/y;
    const scan = codeScanner(t, true);
    // The lines with code the next line can be in, the one nearest above
    // it last, after a root at column 0, as { old, now, kinds, align,
    // ends, item, span }: the width of its indent before and after (the
    // same outside the spans), the brackets (and tags) it leaves open, as
    // codeScanner's kinds, the column of what follows the last of them (-1
    // for nothing), its code's last character, how much deeper its text
    // after a list's mark is, and the span it's in (-1 for none).
    const levels = [{ old: 0, now: 0, kinds: [], align: -1, ends: "", item: 0, span: -1 }], edits = [];
    // The level (an index in levels) of a line `o` deep, by old(level):
    // the deepest not deeper, or the next if that's nearer.
    const levelAt = (o, old) => {
        let k = levels.length - 1;
        while (k > 0 && old(levels[k]) > o)
            k--;
        if (k + 1 < levels.length && old(levels[k + 1]) - o < o - old(levels[k]))
            k++;
        return k;
    };
    // What closing the brackets `kinds` (in order) of the lines above
    // closes, as = has it: each the last still open of its kind, and those
    // after it. Gives { at, left }: the level whose line opened the
    // outermost, and what it leaves open of that line's; null if none.
    const openerOf = kinds => {
        const rest = [];
        let j = levels.length - 1, at = -1;
        for (const k of kinds) {
            for (; j > 0; j--) {
                const open = rest[j] || (rest[j] = levels[j].kinds.slice());
                const x = open.lastIndexOf(k);
                if (x >= 0) {
                    open.length = x;
                    at = j;
                    break;
                }
            }
            if (j === 0)
                break;
        }
        return at > 0 ? { at: at, left: rest[at] } : null;
    };
    const last = spans[spans.length - 1].to;
    // The span whose first line is placed, and how far that moved.
    let s = 0, placed = -1, moved = 0;
    // A level's width before, as span s's lines had it.
    const oldOf = l => l.span === s ? l.old : l.now - moved;
    // Whether l opens a level for the next line, in brackets left open
    // above it (`inside`) or not: there, a : ends a dict's key.
    const opensFor = (l, inside) => forces(l) || !inside && opens(l);
    for (let ls = 0; ls <= last; ) {
        let le = t.indexOf("\n", ls);
        if (le < 0)
            le = t.length;
        while (s < spans.length && spans[s].to < ls)
            s++;
        const inRange = s < spans.length && spans[s].from <= ls;
        const ts = textStart(ls), first = firstOf(ls, le);
        const read = scan(first, le), tokens = read.tokens;
        if (first >= le) {
            if (inRange && first > ts && !(read.inComment && read.inComment.keep))
                edits.push({ start: ts, end: first, text: "" });
            ls = le + 1;
            continue;
        }
        const o = widthOf(ts, first), p = levels[levels.length - 1];
        let end = read.codeEnd;
        while (end > read.codeStart && isBlank(t[end - 1]))
            end--;
        // A line that starts a """ string has code, which ends with it.
        const string = read.comment !== null && read.comment !== read.inComment && quoted(read.comment);
        const code = end > read.codeStart || string;
        // The brackets it leaves open, closes of lines above (the kinds),
        // and starts by closing (as many).
        const still = [], kinds = [], closes = [];
        let lead = 0;
        for (let at = first; lead < tokens.length && tokens[lead].close && tokens[lead].at === at; lead++) {
            at = tokens[lead].end;
            while (at < le && isBlank(t[at]))
                at++;
        }
        for (const k of tokens) {
            let x = still.length - 1;
            if (k.close) {
                while (x >= 0 && still[x].kind !== k.kind)
                    x--;
                if (x >= 0)
                    still.length = kinds.length = x;
                else
                    closes.push(k.kind);
            } else {
                still.push(k);
                kinds.push(k.kind);
            }
        }
        const line = { old: o, now: o, kinds: kinds, align: -1,
            ends: string ? "\"" : code ? t[end - 1] : "", item: 0, span: inRange ? s : -1 };
        let inside = false;
        for (let k = levels.length - 1; k > 0 && !inside; k--)
            inside = levels[k].kinds.length > 0;
        let n = o;
        if (inRange) {
            const closing = code && lead && !read.inComment ? openerOf(closes.slice(0, lead)) : null;
            if (read.inComment) {
                n = read.inComment.keep ? o : Math.max(0, o + read.inComment.indent);
            } else if (closing) {
                // Or as much deeper than it as it was, in the span (under
                // the last line in them, as Python's style lets it be).
                const l = levels[closing.at];
                n = placed === s && l.span === s && o > l.old ? l.now + o - l.old : l.now;
            } else if (placed !== s) {
                if (opensFor(p, inside)) {
                    n = p.align >= 0 ? p.align : p.now + step;
                } else {
                    n = levels[levelAt(o, l => l.now)].now;
                    if (n === p.now && p.item && o >= p.now + p.item)
                        n = p.now + p.item;
                    // Deep enough for the line below, if the line is alone:
                    // a level above it if it opens one, else as deep.
                    const b = below(le, spans[s]), at = code && opens(line) ? b - step : b;
                    if (at > n && levels.some(l => l.now === at))
                        n = at;
                }
            } else {
                // As deep as it was from the line above (always, for a
                // line of only a comment), but a line not deeper than a
                // bracket or \ above it, one a column deeper than a line
                // that opens none, and one shallower out of brackets, which
                // goes at a level.
                const d = o - oldOf(p);
                if (!code)
                    n = Math.max(0, p.now + d);
                else if (d <= 0 && forces(p))
                    n = p.align >= 0 ? p.align : p.now + step;
                else if (d > 0)
                    n = p.now + (opens(p) || inside || d > 1 ? d : p.item && d >= p.item ? p.item : 0);
                else
                    n = inside ? Math.max(0, p.now + d) : levels[levelAt(o, oldOf)].now;
            }
            if (placed !== s) {
                placed = s;
                moved = n - o;
            }
            const text = indentOf(n);
            if (text !== t.slice(ts, first))
                edits.push({ start: ts, end: first, text: text });
        }
        if (read.comment && read.comment.indent === null) {
            read.comment.indent = n - o;
            // A string's lines are its text: they move with it only if it
            // starts its line, as a docstring, whose indent goes.
            read.comment.keep = quoted(read.comment) && !/^[rbfu]{0,2}$/i.test(t.slice(first, read.codeEnd));
        }
        if (code) {
            line.now = n;
            item.lastIndex = first;
            const m = "-*+0123456789".includes(t[first]) ? item.exec(t) : null;
            line.item = m ? m[0].length : 0;
            const k = still.length ? still[still.length - 1] : null;
            let after = k ? k.end : end;
            while (after < end && isBlank(t[after]))
                after++;
            if (k && "([{".includes(k.kind) && after < end)
                line.align = n + widthOf(first, after);
            // A line that closes what one above opened, goes on after a \,
            // or after a string or comment from the line above, is at that
            // one's level, for the lines after it.
            const opened = closes.length ? openerOf(closes)
                : (p.ends === "\\" || read.inComment) && levels.length > 1
                ? { at: levels.length - 1, left: p.kinds.slice() } : null;
            if (opened && (read.inComment || levels[opened.at].now <= n)) {
                const l = levels[opened.at];
                line.old = l.old;
                line.now = l.now;
                line.span = l.span;
                line.kinds = opened.left.concat(line.kinds);
                line.item = 0;
                levels.length = opened.at;
            } else if (read.inComment) {
                ls = le + 1;
                continue;
            }
            // In place of those it's as shallow as: one at its level that
            // was shallower before keeps that, as a line a column off
            // joins it.
            while (levels.length > 1 && levels[levels.length - 1].now >= line.now) {
                const l = levels.pop();
                if (l.now === line.now && l.span === line.span && l.span >= 0)
                    line.old = Math.min(line.old, l.old);
            }
            levels.push(line);
        }
        ls = le + 1;
    }
    return edits;
}

// ---- Case ------------------------------------------------------------------

// Moves each ASCII letter 13 places along the alphabet.
function rot13(s) {
    return s.replace(/[a-zA-Z]/g, c => {
        const base = c <= "Z" ? 65 : 97;
        return String.fromCharCode((c.charCodeAt(0) - base + 13) % 26 + base);
    });
}

function toggleCase(s) {
    let r = "";
    for (let i = 0; i < s.length; i++) {
        const c = s[i], u = c.toUpperCase();
        r += c === u ? c.toLowerCase() : u;
    }
    return r;
}

// ---- Search ----------------------------------------------------------------

// s with the characters that mean something in a regular expression escaped.
function escapeRegExp(s) {
    return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// Whether a search for pattern ignores case, as vim's 'smartcase' does: it
// does unless the pattern has an uppercase letter. In a regular expression
// (regex), the letters of an escape don't count (`\S`, `\x4A`, `\p{Lu}`,
// `\k<Name>`), nor a group's name (`(?<Name>`) or a verb (`(*UCP)`).
function ignoresCase(pattern, regex) {
    const s = regex ? pattern.replace(/\\(?:x\{[0-9a-fA-F]*\}?|x[0-9a-fA-F]{0,2}|u\{?[0-9a-fA-F]*\}?|[pP]\{[^}]*\}?|[pPc][^]?|[kgNo]\{[^}]*\}?|[kg]<[^>]*>?|[kg]'[^']*'?|[^])|\(\?P?[<'][A-Za-z_]\w*[>']|\(\?P[=>]\w*|\(\*[A-Z_]+/g, "") : pattern;
    return s === s.toLowerCase();
}

// A regular expression to look for in texts: `source`, ignoring case with
// `ignoreCase`, where ^ and $ are a line's. With `engine` (System), it's
// PCRE2's (see native.h), which has a look behind (`(?<!a)b`), `(?i)`,
// `a++`, `(?>a)` and `\p{L}`; without one (the tests have no System), QML's
// RegExp, which has none of those. Either way, it has
//   error: why `source` isn't a regular expression (then nothing else), or ""
//   first(t, from): the first match that starts at `from` or after, or null
//   all(t, from, to, limit, perLine): the matches that start from `from` up
//     to `to` (the whole of t without them), at most `limit`, in order, none
//     overlapping; after a match of nothing, the next is looked for a
//     character on. With `perLine`, only the first that starts on each line.
//   before(t, at): where the last match that starts before `at` starts
//     (`before`), and where the last of all does (`last`, only looked for
//     without a `before`), -1 for none
// A match is as RegExp's: the text it took, then each group's (undefined
// for one that took no part), with `index`, `end` and, if a group has a
// name, `groups`, by name.
function regExp(source, ignoreCase, engine) {
    return engine ? nativeRegExp(source, ignoreCase ? "i" : "", engine) : scriptRegExp(source, ignoreCase ? "gmi" : "gm");
}

const noLimit = 0x7fffffff;

// Where the match after m (see regExp) is looked for in t: after it, or a
// whole character on if it's of nothing.
function afterMatch(t, m) {
    return m.end > m.index ? m.end : m.end + (isLowSurrogate(t, m.end + 1) ? 2 : 1);
}

function nativeRegExp(source, flags, engine) {
    const error = engine.regexError(source, flags);
    if (error)
        return { error: error };
    // Only asked for if a group can have a name: (?<a>, (?P<a> or (?'a'.
    const names = /\(\?(?:P?<[^=!]|')/.test(source) ? engine.regexGroupNames(source, flags) : null;
    // bytes is System's regexMatches: a match's size, then each match's
    // numbers.
    const read = (t, bytes) => {
        const found = new Int32Array(bytes);
        const matches = [], size = found.length > 0 ? found[0] : 0;
        for (let i = 1; i + size <= found.length; i += size) {
            const m = [];
            for (let g = 0; g < size; g += 2)
                m.push(found[i + g] < 0 ? undefined : t.slice(found[i + g], found[i + g + 1]));
            m.index = found[i];
            m.end = found[i + 1];
            if (names) {
                m.groups = {};
                for (let g = 1; g < names.length; g++) {
                    if (names[g])
                        m.groups[names[g]] = m[g];
                }
            }
            matches.push(m);
        }
        return matches;
    };
    // An l in the flags asks for the first on each line.
    const all = (t, from, to, limit, perLine) => read(t, engine.regexMatches(t, source, perLine ? flags + "l" : flags,
        from || 0, to === undefined ? t.length : to, limit === undefined ? noLimit : limit));
    return {
        error: "",
        first: (t, from) => all(t, from, t.length, 1, false)[0] || null,
        all: all,
        before: (t, at) => {
            const found = engine.regexBefore(t, source, flags, at);
            return { before: found[0], last: found[1] };
        }
    };
}

function scriptRegExp(source, flags) {
    let re;
    try {
        // with the u flag if it can be, so . is an emoji, not half of one
        re = new RegExp(source, flags + "u");
    } catch (e) {
        try {
            // e.g. "\-" or vim's "\<", which are fine without the u flag
            re = new RegExp(source, flags);
        } catch (e2) {
            return { error: e2.message };
        }
    }
    const next = (t, from) => {
        if (from > t.length)
            return null;
        re.lastIndex = from;
        const m = re.exec(t);
        if (m)
            m.end = m.index + m[0].length;
        return m;
    };
    return {
        error: "",
        first: next,
        all: (t, from, to, limit, perLine) => {
            const found = [];
            if (to === undefined)
                to = t.length;
            if (limit === undefined)
                limit = noLimit;
            for (let at = from || 0, m; found.length < limit && (m = next(t, at)) !== null && m.index <= to;) {
                found.push(m);
                at = afterMatch(t, m);
                if (perLine) {
                    const nl = t.indexOf("\n", m.index);
                    if (nl < 0)
                        break;
                    at = Math.max(at, nl + 1);
                }
            }
            return found;
        },
        before: (t, at) => {
            let before = -1, last = -1;
            for (let from = 0, m; (m = next(t, from)) !== null; from = afterMatch(t, m)) {
                if (m.index >= at && before >= 0)
                    break;
                last = m.index;
                if (m.index < at)
                    before = m.index;
            }
            return { before: before, last: last };
        }
    };
}

// What a search for pattern (vim's, the help's) looks for (see regExp). A
// pattern that isn't a valid regular expression (e.g. while it's still
// being typed) is searched for literally. Either way, one without an
// uppercase letter ignores case (smart case), unless `ignoreCase` says
// (:s's i and I).
function searchRegExp(pattern, ignoreCase, engine) {
    const ignores = regex => ignoreCase === undefined ? ignoresCase(pattern, regex) : ignoreCase;
    const re = regExp(pattern, ignores(true), engine);
    return re.error ? regExp(escapeRegExp(pattern), ignores(false), engine) : re;
}

// ---- Code ------------------------------------------------------------------
// `code` in the help's texts and tips, in the editor's font on a shade of
// its own (see HelpPanel's CodeText and CodeLabel).

// Text with `code` as the text it shows: each code without its
// backticks, and the spaces between collapsed, as rich text shows
// them; and where each code is in it, with the help topic it's a link to
// (`link`, see helpTopic; null for most). `plain` text is as it is.
function parseCode(text, plain) {
    if (plain)
        return { text: text, codes: [] };
    const codes = [];
    let shown = "";
    text.split("`").forEach((part, i) => {
        if (i % 2 === 1)
            codes.push({ start: shown.length, text: part, link: helpTopic(part) });
        else
            part = part.replace(/ +/g, " ");
        shown += part;
    });
    return { text: shown, codes: codes };
}

// The help topic a code is a link to, if it's what's typed to show one
// (`:h pick`, `:help set`; "" for `:h` alone, the help as it opens), or
// null: what shows the code as a link opens it on a click (see HelpLink).
function helpTopic(code) {
    const m = /^:h(?:elp)?(?: (\S+))?$/.exec(code);
    return m ? m[1] || "" : null;
}

// The rich text that shows parsed text (see parseCode): its codes in
// `family` (the editor's font), with letter spacing (`padding`) on the
// characters before and at the end of each, which makes room for its
// shade and copies as nothing, and the search matches in `marks` ([start,
// end, current]) in black, as they're on a highlight. Spaces in a code (or
// in plain text) don't break or collapse, and copy as spaces. With a
// `linkColor`, the codes that are links to the help are in it (their
// underline is HelpLink's, as rich text's would go on under a code's
// letter spacing).
function codeHtml(parsed, marks, plain, family, padding, linkColor) {
    const t = parsed.text;
    const inCode = 1, spaced = 2, marked = 4, linked = 8;
    const flags = new Uint8Array(t.length);
    // Letter spacing goes after a character, so on both of a pair of
    // surrogates.
    const space = i => {
        flags[i] |= spaced;
        if (i > 0 && /[\udc00-\udfff]/.test(t[i]))
            flags[i - 1] |= spaced;
    };
    for (const code of parsed.codes) {
        const end = code.start + code.text.length;
        const kind = inCode | (linkColor && code.link !== null ? linked : 0);
        for (let i = code.start; i < end; i++)
            flags[i] |= kind;
        if (code.start > 0)
            space(code.start - 1);
        space(end - 1);
    }
    for (const mark of marks) {
        for (let i = mark[0]; i < mark[1]; i++)
            flags[i] |= marked;
    }
    let html = "";
    for (let i = 0, j; i < t.length; i = j) {
        const f = flags[i];
        for (j = i + 1; j < t.length && flags[j] === f;)
            j++;
        let run = t.slice(i, j).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        if (plain || f & inCode)
            run = run.replace(/ /g, " ");
        // One character in the document, as the line break is.
        if (plain)
            run = run.replace(/\n/g, "<br>");
        const style = (f & inCode ? "font-family:'" + family + "';" : "")
            + (f & spaced ? "letter-spacing:" + padding + "px;" : "")
            + (f & marked ? "color:black;" : f & linked ? "color:" + linkColor + ";" : "");
        html += style ? "<span style=\"" + style + "\">" + run + "</span>" : run;
    }
    return html;
}

// ---- Substitute ------------------------------------------------------------

// :s's arguments, from the delimiter on (/pattern/replacement/flags, any
// character but a letter, a digit, a blank, \, " or | in place of /, as in
// vim), as { pattern, replacement, flags }. A backslash keeps the delimiter
// in either (\/ is still a / to a regular expression). The replacement is
// null if its delimiter isn't there (yet), and the flags "" if theirs isn't.
// Null if s doesn't start with a delimiter.
function substituteArgs(s) {
    const d = s[0];
    if (d === undefined || /[\sa-zA-Z0-9\\"|]/.test(d))
        return null;
    let i = 1;
    const part = () => {
        const from = i;
        while (i < s.length && s[i] !== d)
            i += s[i] === "\\" ? 2 : 1;
        return s.slice(from, Math.min(i, s.length));
    };
    const pattern = part();
    if (i++ >= s.length)
        return { pattern: pattern, replacement: null, flags: "" };
    const replacement = part();
    return { pattern: pattern, replacement: replacement, flags: i < s.length ? s.slice(i + 1) : "" };
}

// What replaces the match m (a RegExp result) of :s, from its replacement
// as vim reads it: & and \0 are the match, \1 to \9 its groups, \n and \r
// a line break, \t a tab, \u and \l make the next character upper or lower
// case, \U and \L everything up to \E or \e, and a backslash makes any
// other character itself (\&, \\, the delimiter). ~ is only a ~ (vim's is
// the last replacement, which a path like ~/x would take).
function substitution(replacement, m) {
    let out = "", one = "", all = "";
    const add = s => {
        if (all)
            s = all === "U" ? s.toUpperCase() : s.toLowerCase();
        if (one && s) {
            s = (one === "u" ? s[0].toUpperCase() : s[0].toLowerCase()) + s.slice(1);
            one = "";
        }
        out += s;
    };
    for (let i = 0; i < replacement.length; i++) {
        const c = replacement[i];
        if (c === "&") {
            add(m[0]);
            continue;
        }
        if (c !== "\\" || i + 1 >= replacement.length) {
            add(c);
            continue;
        }
        const d = replacement[++i];
        if (d >= "0" && d <= "9")
            add(m[+d] || "");
        else if (d === "n" || d === "r")
            add("\n");
        else if (d === "t")
            add("\t");
        else if (d === "u" || d === "l")
            one = d;
        else if (d === "U" || d === "L")
            all = d;
        else if (d === "E" || d === "e")
            all = "";
        else
            add(d);
    }
    return out;
}

// Adds the highlight of a match [start, end) to spans, split into one
// { start, end, current } span per line, where current means it's the
// match to show as the current one.
function addHighlight(t, spans, start, end, current) {
    for (let s = start; s < end;) {
        const nl = t.indexOf("\n", s);
        const e = nl < 0 || nl > end ? end : nl;
        if (e > s)
            spans.push({ start: s, end: e, current: current });
        s = e + 1;
    }
}
