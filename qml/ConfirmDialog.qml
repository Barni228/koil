pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A question with vim's :confirm choices, [Y]es, (N)o and (C)ancel, in a box
// over the editor like :help's. y answers yes, n no, and c or Esc cancels;
// Left and Right (or h and l, Tab and Shift+Tab) move the highlight, which
// starts on Yes, and Enter answers the highlighted choice. Its text is in
// the editor's font and can be selected and copied.
Popup {
    id: dialog

    required property Theme theme

    readonly property real zoom: theme.zoom
    property string text
    readonly property var choices: [
        { label: "[Y]es", answer: "yes" },
        { label: "(N)o", answer: "no" },
        { label: "(C)ancel", answer: "cancel" }
    ]
    // The highlighted choice, which Enter answers.
    property int current: 0

    signal yes()
    signal no()

    function ask(question) {
        text = question;
        current = 0;
        open();
    }

    function answer(choice) {
        close();
        if (choice === "yes")
            yes();
        else if (choice === "no")
            no();
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent ? parent.width - 48 * zoom : 500,
        Math.max(label.implicitWidth, buttons.implicitWidth) + 2 * padding)
    padding: 16 * zoom
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    onClosed: label.deselect()

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
            if (event.matches(StandardKey.Copy))
                label.copy();
            else if (event.modifiers & ~(Qt.ShiftModifier | Qt.KeypadModifier))
                return;
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backtab)
                dialog.current = Math.max(0, dialog.current - 1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab)
                dialog.current = Math.min(dialog.choices.length - 1, dialog.current + 1);
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

        TextEdit {
            id: label

            Layout.fillWidth: true
            text: dialog.text
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
