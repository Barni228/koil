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

function lineIndex(t) {
    const fresh = { text: t, starts: [0], done: false };
    if (t.length < indexedLength)
        return fresh;
    const x = lineIndexes.find(x => x.text === t) || fresh;
    lineIndexes = [x].concat(lineIndexes.filter(y => y !== x)).slice(0, 2);
    return x;
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

function firstNonBlank(t, p) {
    let q = lineStart(t, p);
    while (q < t.length && isBlank(t[q]))
        q++;
    return q;
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
    let lo = 0, hi = s.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (s[mid] <= p)
            lo = mid + 1;
        else
            hi = mid;
    }
    return Math.max(1, lo);
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
    let col = 0;
    for (let q = lineStart(t, p); q < p; q = charEnd(t, q))
        col++;
    return col;
}

// Position of column `col` in the line starting at ls, or of the line's
// last character when it's shorter.
function atColumn(t, ls, col) {
    const le = lineEnd(t, ls);
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
    const i = pairs.indexOf(t[q]);
    const open = pairs[i & ~1], close = pairs[i | 1], step = i % 2 === 0 ? 1 : -1;
    let depth = 0;
    for (let k = q; k >= 0 && k < t.length; k += step) {
        if (t[k] === open)
            depth += step;
        else if (t[k] === close)
            depth -= step;
        if (depth === 0)
            return { pos: k, type: "inclusive" };
    }
    return null;
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
