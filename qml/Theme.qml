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
    // Behind a hovered button, and a checked one.
    readonly property color hover: dark ? "#26ffffff" : "#1a000000"
    readonly property color checked: Qt.rgba(accent.r, accent.g, accent.b, 0.25)
    readonly property color error: dark ? "#f48771" : "#c42b1c"
    // Text that matters less, like a hint.
    readonly property color dim: Qt.tint(base, dark ? "#a0ffffff" : "#a0000000")
    // A box over the editor (see Panel), and its border.
    readonly property color panel: Qt.tint(base, dark ? "#12ffffff" : "#08000000")
    readonly property color panelBorder: Qt.tint(base, dark ? "#40ffffff" : "#30000000")
    // A text field.
    readonly property color field: dark ? Qt.tint(base, "#1effffff") : base
    // Behind code in a box, like a tooltip's shortcut (over what's behind
    // the box, which shows through).
    readonly property color code: dark ? "#26ffffff" : "#14000000"
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

    // The color of a warning's or an error's squiggle, message and icon.
    function severityColor(severity) {
        if (severity === "error")
            return dark ? "#f14c4c" : "#e51400";
        return dark ? "#ff9d3b" : "#e07000";
    }
}
