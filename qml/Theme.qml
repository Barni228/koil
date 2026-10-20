import QtQuick

// The colors and sizes the app's own controls share (the hover box, the
// find bar, :help, :confirm, Settings). They come from the editor's palette,
// so they follow the light or dark theme.
QtObject {
    id: theme

    // The editor's palette and font.
    required property Palette palette
    required property font font
    // How much bigger than by default the text is. Every text in the app
    // follows the zoom (Cmd+ and Cmd-), not just the editor's, so new UI
    // must scale its sizes by it too.
    property real zoom: 1

    // The palette's colors. When the light or dark theme changes, the
    // palette emits only `changed`, not a signal per color, so bindings on
    // its colors (palette.base) would keep the old ones. Use these instead.
    property color base
    property color window
    property color text
    property color windowText
    property color accent
    property color highlight
    property color highlightedText
    property color placeholderText

    function readPalette() {
        base = palette.base;
        window = palette.window;
        text = palette.text;
        windowText = palette.windowText;
        accent = palette.accent;
        highlight = palette.highlight;
        highlightedText = palette.highlightedText;
        placeholderText = palette.placeholderText;
    }

    onPaletteChanged: readPalette()
    Component.onCompleted: readPalette()

    readonly property Connections paletteChanges: Connections {
        target: theme.palette

        function onChanged() {
            theme.readPalette();
        }
    }

    readonly property bool dark: base.hslLightness < 0.5
    // Behind the marked lines (see Vim's `marked`): the selection's color,
    // paler, as they're like a selection, but not what the cursor selects.
    readonly property color marked: Qt.rgba(highlight.r, highlight.g, highlight.b, 0.6)
    // Behind what the find bar finds in (Find in Selection): paler still.
    readonly property color findScope: Qt.rgba(highlight.r, highlight.g, highlight.b, 0.3)
    // Behind a hovered button, and a checked one.
    readonly property color hover: dark ? "#26ffffff" : "#1a000000"
    readonly property color checked: Qt.rgba(accent.r, accent.g, accent.b, 0.25)
    readonly property color error: dark ? "#f48771" : "#c42b1c"
    // Text that matters less, like a hint, and less still, like the line
    // numbers.
    readonly property color dim: Qt.tint(base, dark ? "#a0ffffff" : "#a0000000")
    readonly property color faint: Qt.tint(base, dark ? "#80ffffff" : "#80000000")
    // A box over the editor (see Panel), and its border.
    readonly property color panel: Qt.tint(base, dark ? "#12ffffff" : "#08000000")
    readonly property color panelBorder: Qt.tint(base, dark ? "#40ffffff" : "#30000000")
    // A text field, and its border (and a button's) in a window (Settings,
    // Shortcuts).
    readonly property color field: dark ? Qt.tint(base, "#1effffff") : base
    readonly property color fieldBorder: dark ? Qt.tint(window, "#30ffffff") : "#cecece"
    // Behind code in a box, like a tooltip's shortcut (over what's behind
    // the box, which shows through).
    readonly property color code: dark ? "#26ffffff" : "#14000000"
    // A search match, and the current one, under dark text.
    readonly property color searchMatch: "#f5d547"
    readonly property color currentMatch: "#ff9f1a"
    // Behind what was just yanked, for a moment (see Editor's yankFlash),
    // under the text's own colors: VS Code's blue, and in a light theme a
    // tint of it, under dark text.
    readonly property color yanked: dark ? "#007ad4" : "#4d007ad4"
    // The name of a key in keys written out, like <CR> (a shortcut's).
    readonly property color specialKey: dark ? "#c586c0" : "#af00db"
    // A dir's name in Koil's listing, and the path it lists.
    readonly property color directory: dark ? "#6cb6ff" : "#0b62c4"
    // The parts of a regex on the listing's path line (see listing::Span),
    // as VS Code colors them.
    readonly property var regexColors: dark ? {
        pattern: String(text),
        escape: "#d7ba7d",
        class: "#ce9178",
        quantifier: "#dcdcaa",
        group: "#c586c0",
        anchor: "#4ec9b0"
    } : {
        pattern: String(text),
        escape: "#ee0000",
        class: "#a31515",
        quantifier: "#795e26",
        group: "#af00db",
        anchor: "#267f99"
    }

    // A file's colors (see syntax.rs), for each kind of part in the order
    // of SyntaxKind: strings, their escapes, numbers, comments, paths and
    // URLs (which are underlined too). Paths are in the dirs' color, as in
    // the listing. A function, as changeColor is.
    function syntaxColors() {
        return dark ? ["#98c379", "#56b6c2", "#d19a66", "#8b949e", String(directory), String(directory)]
            : ["#3d8b37", "#0184bc", "#986801", "#6e7781", String(directory), String(directory)];
    }
    // Behind a bracket and the one it matches (see Editor's brackets), and
    // around them.
    readonly property color bracketMatch: dark ? "#2effffff" : "#1f000000"
    readonly property color bracketBorder: dark ? "#80ffffff" : "#66000000"

    // A color of `pair`, [dark, light], as the theme is.
    function pick(pair) {
        return pair[dark ? 0 : 1];
    }

    // The color of a kind of change in the confirmations (see
    // ConfirmDialog's keywords): "create", "delete", "rename" (or move) or
    // "copy". A function, as an object of constant colors in a binding
    // (`dark ? { create: "#73c991", … } : { … }`) came out undefined in the
    // compiled app, though qmltestrunner had it.
    function changeColor(kind) {
        return pick({ create: ["#73c991", "#388a34"], delete: ["#f14c4c", "#e51400"],
            rename: ["#e2c08d", "#895503"] }[kind] || ["#4fc1ff", "#0070c1"]);
    }

    // The color of a kind of part of the command line (see Vim's
    // commandLineParts): "range", "command", "file" (a path, in the dirs'
    // color), "escape" or "option".
    function commandColor(kind) {
        if (kind === "file")
            return String(directory);
        return pick({ range: ["#d19a66", "#986801"], command: ["#c586c0", "#af00db"],
            escape: ["#56b6c2", "#0184bc"] }[kind] || ["#9cdcfe", "#001080"]);
    }

    // The color of a warning's or an error's squiggle, message and icon.
    function severityColor(severity) {
        return severity === "error" ? changeColor("delete") : pick(["#ff9d3b", "#e07000"]);
    }
}
