pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// A list under `field`, in a window of its own, so the window the field is
// in doesn't cut it off: the Settings window's fonts and shells, and the
// macros a shortcut can run. Its delegates are DropOptions. Unless it
// `takesKeys`, the field keeps them, but for Esc, which closes it.
T.Popup {
    id: drop

    required property Theme theme
    required property Item field
    property real maxHeight: 320 * theme.zoom
    property alias model: view.model
    property alias delegate: view.delegate
    readonly property alias view: view
    property bool takesKeys: false
    // What it says while it's empty, `emptySize` big.
    property string emptyText
    property real emptySize: Math.round(13 * theme.zoom)

    // A key pressed while it `takesKeys`.
    signal keyPressed(var event)

    y: field.height + 2 * theme.zoom
    width: field.width
    height: Math.min(implicitContentHeight + topPadding + bottomPadding, maxHeight)
    padding: 4 * theme.zoom
    popupType: Popup.Window
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    focus: takesKeys

    contentItem: ListView {
        id: view

        focus: drop.takesKeys
        clip: true
        implicitHeight: Math.max(contentHeight, 24 * drop.theme.zoom)
        boundsBehavior: Flickable.StopAtBounds
        ScrollIndicator.vertical: ScrollIndicator {}
        Keys.onPressed: event => drop.keyPressed(event)

        Text {
            anchors.centerIn: parent
            visible: view.count === 0
            text: drop.emptyText
            font.pixelSize: drop.emptySize
            color: drop.theme.windowText
            opacity: 0.6
            textFormat: Text.PlainText
        }
    }
    background: Rectangle {
        radius: 4 * drop.theme.zoom
        color: drop.theme.field
        border.color: drop.theme.fieldBorder
    }
}
