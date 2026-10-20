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

function nextWordStart(t, p, big) {
    const n = t.length;
    if (p >= n)
        return n;
    const c = charClass(t[p], big);
    if (c !== 0)
        while (p < n && charClass(t[p], big) === c)
            p++;
    while (p < n) {
        if (t[p] === "\n") {
            p++;
            if (p < n && t[p] === "\n")
                return p; // an empty line counts as a word
            continue;
        }
        if (charClass(t[p], big) !== 0)
            return p;
        p++;
    }
    return n;
}

function prevWordStart(t, p, big) {
    let q = p - 1;
    while (q > 0 && charClass(t[q], big) === 0) {
        if (t[q] === "\n" && t[q - 1] === "\n")
            return q;
        q--;
    }
    if (q <= 0)
        return 0;
    const c = charClass(t[q], big);
    while (q > 0 && charClass(t[q - 1], big) === c)
        q--;
    return q;
}

function wordEnd(t, p, big) {
    const n = t.length;
    let q = charEnd(t, p);
    while (q < n && charClass(t[q], big) === 0)
        q++;
    if (q >= n)
        return p;
    const c = charClass(t[q], big);
    for (let e = charEnd(t, q); e < n && charClass(t[e], big) === c; e = charEnd(t, q))
        q = e;
    return q;
}

function prevWordEnd(t, p, big) {
    let q = p;
    const c = charClass(t[q], big);
    if (c !== 0)
        while (q > 0 && charClass(t[q - 1], big) === c)
            q--;
    q--;
    while (q > 0 && charClass(t[q], big) === 0) {
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

// The indents `=` gives the lines in `spans` ({ from, to }: the starts of
// a span's first and last lines, in order), by the brackets (( [ {) and
// the tags around them, as vim's C-indenting does without knowing the
// language: a line in brackets goes `unit` deeper than the line they
// open on, one that starts by closing them as deep as that line, a blank
// line has none, and a line in no brackets keeps its own (a block of
// Python or YAML stays as it is). Brackets in strings and comments
// (those syntax.rs colors; `slashes`: // and /* */ ones) don't count. In
// a /* */ comment, a line starting with * goes a space deeper than the
// comment's first line, and others stay. A line's indent starts where
// textStart(its start) says (after the listing's prefix). Gives the
// edits, as { start, end, text }, for the lines whose indent changes.
function reindent(t, spans, unit, slashes, textStart) {
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
    // Whether a \ escapes the character at i (an odd number of them before it).
    const escaped = i => {
        let n = 0;
        while (i - n - 1 >= 0 && t.charCodeAt(i - n - 1) === 92)
            n++;
        return n % 2 === 1;
    };
    const signs = /[\/<#"'`()[\]{}]/g;
    // In a comment going on to the next line: { close, indent }, its end
    // and the indent of the line it starts on.
    let comment = null;
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
        // The tokens of the line: brackets and tags, as { kind, close, at, end }.
        const tokens = [], inComment = comment;
        let i = first;
        if (comment) {
            const end = t.indexOf(comment.close, first);
            if (end < 0 || end >= le) {
                i = le;
            } else {
                i = end + comment.close.length;
                comment = null;
            }
        }
        while (i < le) {
            // To the next character that can start something.
            signs.lastIndex = i;
            const found = signs.exec(t);
            if (!found || found.index >= le)
                break;
            i = found.index;
            const c = found[0];
            if (slashes && c === "/" && t[i + 1] === "/" && blankOr(i - 1, ";{}"))
                break;
            const close = slashes && c === "/" && t[i + 1] === "*" && blankOr(i - 1, "({[,;=") ? "*/"
                : t.startsWith("<!--", i) ? "-->" : null;
            if (close) {
                const end = t.indexOf(close, i + 2);
                if (end < 0 || end >= le) {
                    comment = { close: close, indent: null };
                    break;
                }
                i = end + close.length;
                continue;
            }
            if (c === "#" && blankOr(i - 1, "") && (i + 1 >= le || isBlank(t[i + 1])
                    || t[i + 1] === "!" && t[i + 2] !== "[" || "#-=*/~:+|".includes(t[i + 1])))
                break;
            if ((c === "\"" || c === "`" || c === "'" && !isWordAt(i - 1)) && t[i - 1] !== "\\") {
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
        // Its indent: as its opener's line, if it starts by closing (the
        // outermost it closes), else a level deeper than the line the
        // innermost level opened on.
        let indent = null, k = 0, popped = null;
        if (inComment) {
            indent = inComment.indent !== null && t[first] === "*" ? inComment.indent + " " : null;
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
        if (comment && comment.indent === null)
            comment.indent = now;
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
// (regex), the letters of an escape don't count (`\S`, `\x4A`, `\cM`).
function ignoresCase(pattern, regex) {
    const s = regex ? pattern.replace(/\\(?:u\{?[0-9a-fA-F]*\}?|x[0-9a-fA-F]{0,2}|c[a-zA-Z]?|[^])/g, "") : pattern;
    return s === s.toLowerCase();
}

// What a search for pattern (vim's, the help's) looks for. A pattern that
// isn't a valid regular expression (e.g. while it's still being typed) is
// searched for literally. Either way, one without an uppercase letter
// ignores case (smart case), unless `ignoreCase` says (:s's i and I).
function searchRegExp(pattern, ignoreCase) {
    const flags = regex => (ignoreCase === undefined ? ignoresCase(pattern, regex) : ignoreCase) ? "gmi" : "gm";
    try {
        return new RegExp(pattern, flags(true));
    } catch (e) {
        return new RegExp(escapeRegExp(pattern), flags(false));
    }
}

// ---- Code ------------------------------------------------------------------
// `code` in the help's texts and tips, in the editor's font on a shade of
// its own (see HelpPanel's CodeText and CodeLabel).

// Text with `code` as the text it shows: each code without its
// backticks, and the spaces between collapsed, as rich text shows
// them; and where each code is in it. `plain` text is as it is.
function parseCode(text, plain) {
    if (plain)
        return { text: text, codes: [] };
    const codes = [];
    let shown = "";
    text.split("`").forEach((part, i) => {
        if (i % 2 === 1)
            codes.push({ start: shown.length, text: part });
        else
            part = part.replace(/ +/g, " ");
        shown += part;
    });
    return { text: shown, codes: codes };
}

// The rich text that shows parsed text (see parseCode): its codes in
// `family` (the editor's font), with letter spacing (`padding`) on the
// characters before and at the end of each, which makes room for its
// shade and copies as nothing, and the search matches in `marks` ([start,
// end, current]) in black, as they're on a highlight. Spaces in a code (or
// in plain text) don't break or collapse, and copy as spaces.
function codeHtml(parsed, marks, plain, family, padding) {
    const t = parsed.text;
    const inCode = 1, spaced = 2, marked = 4;
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
        for (let i = code.start; i < end; i++)
            flags[i] |= inCode;
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
            + (f & spaced ? "letter-spacing:" + padding + "px;" : "") + (f & marked ? "color:black;" : "");
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
