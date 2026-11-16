import QtQuick

// A link to the help, over a code that's one (`:h pick`, see
// Txt.helpTopic) in a CodeLabel or the help's own texts: the code's text
// is in the link's color (see Txt.codeHtml), and this, over its shade on a
// line, underlines it, makes the pointer a hand and shades it more with
// the pointer on it. A click is `followed`, for whoever shows it to open
// the topic.
MouseArea {
    id: link

    required property Theme theme
    // The code's shade on the line, how far it reaches past the code's
    // text on either side, and how far over its bottom the text's
    // baseline is.
    required property rect shade
    required property real inset
    required property real descent
    property string topic
    signal followed

    x: shade.x
    y: shade.y
    width: shade.width
    height: shade.height
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    Accessible.role: Accessible.Link
    Accessible.name: topic ? qsTr("Help on %1").arg(topic) : qsTr("Help")
    Accessible.onPressAction: followed()
    onClicked: followed()

    Rectangle {
        anchors.fill: parent
        visible: link.containsMouse
        radius: 3 * link.theme.zoom
        color: link.theme.hover
    }
    Rectangle {
        x: link.inset
        y: Math.round(link.height - link.descent + link.theme.zoom)
        width: link.width - 2 * link.inset
        height: Math.max(1, Math.round(link.theme.zoom))
        color: link.theme.link
        opacity: link.containsMouse ? 1 : 0.7
    }
}
