import QtQuick
import QtQuick.Controls

// A box with a check in it, and its label after it, in a window (the
// Settings window's line numbers, the Shortcuts form's modes and Enabled),
// for what can be on or off apart from what's beside it: two of them, rather
// than a choice of neither, one, the other or both. Tab reaches it, and
// Space or Enter flips it (the Shortcuts form's Enter saves first). Not
// `checkable` unless set: like Toggle, it shows `checked` and emits
// `clicked`, so a binding of `checked` to a setting stays.
AbstractButton {
    id: check

    required property Theme theme

    readonly property real zoom: theme.zoom

    // As tall as the other controls, so the rows line up.
    implicitWidth: implicitContentWidth
    implicitHeight: Math.max(26 * zoom, implicitContentHeight)
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checkable: true
    Accessible.checked: checked
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()

    // Its ring, around the box and the label, as the box is the accent's
    // color when on.
    background: Rectangle {
        x: -4 * check.zoom
        y: Math.round((check.height - height) / 2)
        width: check.width + 8 * check.zoom
        height: check.implicitContentHeight + 6 * check.zoom
        radius: 4 * check.zoom
        color: "transparent"
        border.color: check.visualFocus ? check.theme.accent : "transparent"
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
            id: row

            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * check.zoom

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 16 * check.zoom
                height: 16 * check.zoom
                radius: 3 * check.zoom
                color: {
                    const color = check.checked ? check.theme.accent : check.theme.field;
                    return check.pressed ? Qt.darker(color, 1.15) : check.hovered ? Qt.tint(color, check.theme.hover) : color;
                }
                border.color: check.checked || check.visualFocus ? check.theme.accent : check.theme.fieldBorder

                Icon {
                    anchors.centerIn: parent
                    visible: check.checked
                    theme: check.theme
                    path: "M4 8.5 L7 11.5 L12 5"
                    color: check.theme.highlightedText
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: check.text
                font.pixelSize: Math.round(13 * check.zoom)
                color: check.theme.windowText
            }
        }
    }
}
