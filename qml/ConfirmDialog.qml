pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A question with vim's :confirm choices, [Y]es, (N)o and (C)ancel, in a box
// over the editor like :help's, with an optional list under it (what
// applying would do, say), which scrolls if it's long. y answers yes, n no,
// and c or Esc cancels; Left and Right (or h and l, Tab and Shift+Tab) move
// the highlight, which starts on Yes, Enter answers the highlighted choice,
// and j and k (or Up and Down) scroll. Its text is in the editor's font and
// can be selected and copied.
Popup {
    id: dialog

    required property Theme theme

    readonly property real zoom: theme.zoom
    property string text
    property string details
    // What the answers do, and what's done after any of them (see ask).
    property var yesAction: null
    property var noAction: null
    property var afterAction: null
    // Without anything for No to do, No is the same as Cancel, so it's
    // offered alone.
    readonly property var choices: [
        { label: "[Y]es", answer: "yes" },
        { label: "(N)o", answer: "no" }
    ].concat(noAction ? [{ label: "(C)ancel", answer: "cancel" }] : [])
    // The highlighted choice, which Enter answers.
    property int current: 0

    // Asks `question`, with `details` (a list, maybe "") under it. `yes` is
    // what Yes does, and `no` what No does, if anything. `after` runs after
    // either, or if it's closed some other way (the next question, say).
    function ask(question, details, yes, no, after) {
        text = question;
        dialog.details = details || "";
        yesAction = yes;
        noAction = no || null;
        afterAction = after || null;
        current = 0;
        scroller.contentY = 0;
        open();
    }

    function answer(choice) {
        const action = choice === "yes" ? yesAction : choice === "no" ? noAction : null;
        const after = afterAction;
        afterAction = null;
        close();
        if (action)
            action();
        if (after)
            after();
    }

    function scrollBy(dy) {
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, scroller.contentY + dy));
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 500,
        Math.max(label.implicitWidth + scrollBar.width, buttons.implicitWidth) + 2 * padding)
    padding: 16 * zoom
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    onClosed: {
        label.deselect();
        // Closed by a click outside it.
        const after = afterAction;
        afterAction = null;
        if (after)
            after();
    }

    Overlay.modal: Rectangle {
        color: dialog.theme.dark ? "#60000000" : "#30000000"
    }

    background: Panel {
        theme: dialog.theme
        raised: true
    }

    component Choice: AbstractButton {
        id: choice

        required property var modelData
        required property int index
        readonly property bool isCurrent: index === dialog.current

        padding: 4 * dialog.zoom
        leftPadding: 12 * dialog.zoom
        rightPadding: 12 * dialog.zoom
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        text: modelData.label
        onClicked: dialog.answer(modelData.answer)

        background: Rectangle {
            readonly property color accent: dialog.theme.accent

            radius: 4 * dialog.zoom
            color: choice.isCurrent ? Qt.rgba(accent.r, accent.g, accent.b, choice.hovered || choice.pressed ? 0.4 : 0.25)
                : choice.hovered || choice.pressed ? dialog.theme.hover : "transparent"
            border.color: choice.isCurrent ? accent : dialog.theme.panelBorder
        }
        contentItem: Text {
            text: choice.text
            font: dialog.theme.font
            color: dialog.theme.text
            textFormat: Text.PlainText
        }
    }

    contentItem: ColumnLayout {
        spacing: 16 * dialog.zoom
        focus: true

        Keys.onPressed: event => {
            const step = label.implicitHeight / Math.max(1, label.lineCount);
            if (event.matches(StandardKey.Copy))
                label.copy();
            else if (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier))
                return;
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab)
                dialog.current = Math.max(0, dialog.current - 1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab)
                dialog.current = Math.min(dialog.choices.length - 1, dialog.current + 1);
            else if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
                dialog.scrollBy(step);
            else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
                dialog.scrollBy(-step);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                dialog.answer(dialog.choices[dialog.current].answer);
            else if (event.key === Qt.Key_Y)
                dialog.answer("yes");
            else if (event.key === Qt.Key_N)
                dialog.answer("no");
            else if (event.key === Qt.Key_C || event.key === Qt.Key_Escape)
                dialog.answer("cancel");
            else
                return;
            event.accepted = true;
        }

        // Not interactive, since a drag selects text; the wheel scrolls it.
        Flickable {
            id: scroller

            Layout.fillWidth: true
            // As tall as the text, but no taller than the window has room for.
            Layout.preferredHeight: Math.min(label.implicitHeight, (dialog.parent ? dialog.parent.height : 500)
                - 48 * dialog.zoom - 2 * dialog.padding - buttons.implicitHeight - parent.spacing)
            contentWidth: width
            contentHeight: label.implicitHeight
            interactive: false
            clip: true

            ScrollBar.vertical: ScrollBar {
                id: scrollBar
            }

            // The trackpad too, which a WheelHandler leaves out by default.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => dialog.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * 60 * dialog.zoom))
            }

            TextEdit {
                id: label

                // Room for the scroll bar, which the width can't depend on
                // needing: that depends on the height, which depends on it.
                width: scroller.width - scrollBar.width
                text: dialog.details ? dialog.text + "\n\n" + dialog.details : dialog.text
                font: dialog.theme.font
                color: dialog.theme.text
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                readOnly: true
                selectByMouse: true
                // Keys stay with the dialog, which forwards Copy.
                activeFocusOnPress: false
                persistentSelection: true
                selectionColor: dialog.theme.highlight
                selectedTextColor: dialog.theme.highlightedText

                HoverHandler {
                    cursorShape: Qt.IBeamCursor
                }
            }
        }

        Row {
            id: buttons

            Layout.alignment: Qt.AlignRight
            spacing: 8 * dialog.zoom

            Repeater {
                model: dialog.choices

                Choice {}
            }
        }
    }
}
