pragma ComponentBehavior: Bound

import QtQuick
import "text.js" as Txt

// Text with `code` in backquotes (a key, `:set wrap`, a file), each code in
// the editor's font on a shade of its own, as the help shows them: in a
// Tip, and the Settings window's notes. A TextEdit, which tells where the
// codes are, but read-only and never focused. With `links`, a code that
// shows the help (`:h pick`) is a link, and a click on it asks for its
// topic (helpRequested), which whoever shows the label opens in the
// help's window; not in a Tip, which goes as the pointer leaves for it.
TextEdit {
    id: label

    required property Theme theme
    property string markup
    property bool links: false
    signal helpRequested(string topic)
    // How far a code's shade reaches past its text, as in the help.
    readonly property real codePadding: 4 * theme.zoom
    readonly property var parsed: Txt.parseCode(markup, false)
    // The shades are placed once the text is laid out.
    readonly property var layout: [text, width, contentWidth, contentHeight]
    property var shades: []
    // Each link's shades, with its topic: { rect, topic }.
    property var linkShades: []
    readonly property FontMetrics codeMetrics: FontMetrics {
        font.family: label.theme.font.family
        font.pixelSize: label.font.pixelSize
    }
    readonly property FontMetrics textMetrics: FontMetrics {
        font: label.font
    }

    // A shade behind each code: a rectangle a line it's on (a code can
    // break at a `/` or `-`), from `codePadding` before it to where the
    // character after it starts (past its letter spacing), or as far past
    // a line's last character.
    function place() {
        const pad = codePadding, s = [], l = [];
        for (const code of parsed.codes) {
            const end = code.start + code.text.length;
            let from = positionToRectangle(code.start), left = from.x - pad;
            for (let i = code.start + 1; i <= end; i++) {
                const at = positionToRectangle(i);
                if (at.y === from.y && i < end)
                    continue;
                const right = at.y === from.y ? at.x
                    : positionToRectangle(i - 1).x + codeMetrics.advanceWidth(parsed.text[i - 1]) + pad;
                const shade = Qt.rect(left, from.y, right - left, from.height);
                s.push(shade);
                if (links && code.link !== null)
                    l.push({ rect: shade, topic: code.link });
                from = at;
                left = at.x - pad;
            }
        }
        shades = s;
        linkShades = l;
    }

    readOnly: true
    selectByMouse: false
    activeFocusOnPress: false
    textFormat: TextEdit.RichText
    wrapMode: TextEdit.Wrap
    text: Txt.codeHtml(parsed, [], false, theme.font.family, codePadding, links ? String(theme.link) : "")
    Accessible.role: Accessible.StaticText
    Accessible.name: parsed.text
    onLayoutChanged: Qt.callLater(place)

    Repeater {
        model: label.shades

        Rectangle {
            required property rect modelData

            z: -1
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            radius: 3 * label.theme.zoom
            color: label.theme.code
        }
    }
    Repeater {
        model: label.linkShades

        HelpLink {
            required property var modelData

            theme: label.theme
            shade: modelData.rect
            inset: label.codePadding
            descent: Math.max(label.codeMetrics.descent, label.textMetrics.descent)
            topic: modelData.topic
            onFollowed: label.helpRequested(modelData.topic)
        }
    }
}
