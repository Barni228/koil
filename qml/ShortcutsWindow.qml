pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Templates as T

// The user's shortcuts (Koil > Shortcuts…, or a button in Settings): each
// is Space and a key that run keys of theirs, as a macro does (see
// Vim.shortcuts), in normal mode, visual mode or both, with a name, and on
// or off. The list shows each by its name, else its key, else its keys; a
// click on one (or + for a new one) shows all of it in a form, which Save
// saves, used at once (main.qml's saveShortcuts). Its keys can be typed or
// taken from a macro recorded (a register q records into).
Window {
    id: win

    // main.qml's window: the shortcuts, saveShortcuts, Koil's own keys
    // after Space (spaceKeys), and the macros recorded (macroList).
    required property var app
    required property Theme theme

    readonly property real zoom: theme.zoom
    readonly property var shortcuts: app.shortcuts
    readonly property var modes: [
        { label: qsTr("Normal"), value: "normal" },
        { label: qsTr("Visual"), value: "visual" },
        { label: qsTr("Both"), value: "both" }
    ]
    // Whether the form shows, and the shortcut it edits (-1 for a new one).
    property bool editing: false
    property int editIndex: -1
    // What the form has, and why it can't be saved, if it can't.
    readonly property var draft: ({
        name: nameField.input.text.trim(),
        key: keyBox.key,
        macro: macroField.input.text,
        mode: modes[Math.max(0, modeChoice.current)].value,
        enabled: enabledBox.checked
    })
    readonly property string problem: problemOf(draft)
    readonly property bool canSave: draft.macro !== "" && problem === ""

    // How a key after Space is written: "c", or "Space".
    function keyName(key) {
        return key === " " ? "Space" : key;
    }
    // What the list calls a shortcut: its name, else its key, else its keys.
    function titleOf(s) {
        return s.name || (s.key ? "Space " + keyName(s.key) : s.macro);
    }
    function modeLabel(s) {
        return !s.enabled ? qsTr("Off") : s.mode === "both" ? qsTr("Normal, visual")
            : s.mode === "visual" ? qsTr("Visual") : qsTr("Normal");
    }
    // Why the shortcut `d` can't be saved: its key is one of Koil's own
    // after Space, or another shortcut that's on has it in the same mode.
    // "" if it can.
    function problemOf(d) {
        const own = d.key ? app.spaceKeys[d.key] : undefined;
        if (own !== undefined)
            return qsTr("Koil's own Space %1 %2.").arg(keyName(d.key)).arg(own);
        if (!d.key || !d.enabled)
            return "";
        const other = shortcuts.find((s, i) => i !== editIndex && s.enabled && s.key === d.key
            && (s.mode === "both" || d.mode === "both" || s.mode === d.mode));
        if (!other)
            return "";
        const what = other.name || (other.macro.length > 40 ? other.macro.slice(0, 39) + "…" : other.macro);
        const message = other.mode === "normal" ? qsTr("Space %1 already runs “%2” in normal mode.")
            : other.mode === "visual" ? qsTr("Space %1 already runs “%2” in visual mode.")
            : qsTr("Space %1 already runs “%2”.");
        return message.arg(keyName(d.key)).arg(what);
    }

    // Shows the window, with the list, centered near the top of the main
    // window the first time and whenever it was closed.
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
            editing = false;
        }
        show();
        raise();
        requestActivate();
    }
    // Back to the list from the form, on the shortcut it showed.
    function showList(index) {
        editing = false;
        shortcutList.currentIndex = index === undefined ? -1 : index;
        shortcutList.forceActiveFocus();
    }
    // The form for the shortcut at `index`, or for a new one (-1).
    function edit(index) {
        const s = index < 0 ? { name: "", key: "", macro: "", mode: "normal", enabled: true } : shortcuts[index];
        editIndex = index;
        nameField.input.text = s.name;
        keyBox.key = s.key;
        macroField.input.text = s.macro;
        modeChoice.current = Math.max(0, modes.findIndex(m => m.value === s.mode));
        enabledBox.checked = s.enabled;
        editing = true;
        nameField.input.forceActiveFocus();
    }
    function save() {
        if (!canSave)
            return;
        const list = shortcuts.slice();
        if (editIndex < 0)
            list.push(draft);
        else
            list[editIndex] = draft;
        app.saveShortcuts(list);
        showList(editIndex < 0 ? list.length - 1 : editIndex);
    }
    function remove() {
        app.saveShortcuts(shortcuts.filter((s, i) => i !== editIndex));
        showList();
    }
    // A key typed in the form's key box: the key after Space, any that
    // types a character (Backspace: none).
    function typeKey(event) {
        const typed = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier) ? "" : event.text;
        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)
            keyBox.key = "";
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            save();
        else if ([...typed].length === 1 && typed >= " " && typed !== "\x7f")
            keyBox.key = typed;
        else
            return;
        event.accepted = true;
    }

    title: qsTr("Shortcuts")
    flags: Qt.Dialog
    color: theme.window
    // Its size follows the zoom, so it isn't resizable; the list scrolls.
    readonly property int fitWidth: Math.ceil(480 * zoom)
    readonly property int fitHeight: Math.ceil(pages.implicitHeight + 2 * pages.y)

    width: fitWidth
    height: fitHeight
    minimumWidth: fitWidth
    maximumWidth: fitWidth
    minimumHeight: fitHeight
    maximumHeight: fitHeight

    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: win.close()
    }
    // Not while the macros are listed, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: !macroList.visible
        onActivated: win.editing ? win.showList(win.editIndex) : win.close()
    }

    // A small button with an icon, which Tab reaches.
    component WindowButton: IconButton {
        theme: win.theme
        color: win.theme.windowText
        focusPolicy: Qt.TabFocus
    }

    // Keys, as code: in the editor's font, on a shade.
    component KeyCap: Rectangle {
        id: cap

        property string text

        implicitWidth: capText.implicitWidth
        implicitHeight: capText.implicitHeight
        radius: 3 * win.zoom
        color: win.theme.code

        Text {
            id: capText

            leftPadding: 5 * win.zoom
            rightPadding: 5 * win.zoom
            topPadding: 1 * win.zoom
            bottomPadding: 1 * win.zoom
            text: cap.text
            font.family: win.theme.font.family
            font.pixelSize: Math.round(12 * win.zoom)
            color: win.theme.windowText
            textFormat: Text.PlainText
        }
    }

    // A text field, where Return saves the form.
    component Field: Rectangle {
        id: field

        property alias input: fieldInput
        property string label
        property string placeholder
        // Keys, in the editor's font.
        property bool mono
        // Room on the right for a button.
        property real rightRoom: 8 * win.zoom

        implicitWidth: 200 * win.zoom
        implicitHeight: 26 * win.zoom
        radius: 4 * win.zoom
        color: win.theme.field
        border.color: fieldInput.activeFocus ? win.theme.accent : win.theme.fieldBorder

        TextInput {
            id: fieldInput

            x: 8 * win.zoom
            width: field.width - x - field.rightRoom
            height: field.height
            clip: true
            font.family: field.mono ? win.theme.font.family : Application.font.family
            font.pixelSize: Math.round(13 * win.zoom)
            color: win.theme.windowText
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            selectionColor: win.theme.highlight
            selectedTextColor: win.theme.highlightedText
            Accessible.name: field.label
            Keys.onReturnPressed: win.save()
            Keys.onEnterPressed: win.save()

            Text {
                anchors.fill: parent
                visible: !fieldInput.text
                text: field.placeholder
                font: fieldInput.font
                color: win.theme.windowText
                opacity: 0.5
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    component FormLabel: Label {
        font.pixelSize: Math.round(13 * win.zoom)
        color: win.theme.windowText
    }

    // Text that matters less, like a hint.
    component Hint: Text {
        font.pixelSize: Math.round(12 * win.zoom)
        color: win.theme.windowText
        opacity: 0.6
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    // The list and the form, as tall as the taller one.
    StackLayout {
        id: pages

        x: 20 * win.zoom
        y: 16 * win.zoom
        width: win.width - 2 * x
        height: win.height - 2 * y
        currentIndex: win.editing ? 1 : 0

        ColumnLayout {
            spacing: 10 * win.zoom

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * win.zoom

                Hint {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: qsTr("Space and a key of yours, which run keys as a macro does.")
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
                WindowButton {
                    iconPath: "M4 8 H12 M8 4 V12"
                    tip: qsTr("New Shortcut")
                    onClicked: win.edit(-1)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 4 * win.zoom
                color: win.theme.field
                border.color: win.theme.fieldBorder

                ListView {
                    id: shortcutList

                    anchors.fill: parent
                    anchors.margins: 4 * win.zoom
                    clip: true
                    model: win.shortcuts
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: true
                    activeFocusOnTab: true
                    Accessible.name: qsTr("Shortcuts")
                    ScrollIndicator.vertical: ScrollIndicator {}
                    Keys.onReturnPressed: if (currentIndex >= 0) win.edit(currentIndex)
                    Keys.onEnterPressed: if (currentIndex >= 0) win.edit(currentIndex)
                    onActiveFocusChanged: {
                        if (activeFocus && currentIndex < 0 && count)
                            currentIndex = 0;
                    }

                    delegate: AbstractButton {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool current: shortcutList.activeFocus && row.ListView.isCurrentItem

                        width: ListView.view.width
                        implicitHeight: 30 * win.zoom
                        focusPolicy: Qt.NoFocus
                        hoverEnabled: true
                        Accessible.name: win.titleOf(modelData)
                        onClicked: win.edit(index)

                        background: Rectangle {
                            radius: 3 * win.zoom
                            color: row.current ? win.theme.checked : row.hovered ? win.theme.hover : "transparent"
                        }
                        contentItem: RowLayout {
                            spacing: 8 * win.zoom

                            Text {
                                Layout.fillWidth: true
                                leftPadding: 6 * win.zoom
                                text: win.titleOf(row.modelData)
                                // Keys (it has no name) in the editor's font.
                                font.family: row.modelData.name ? Application.font.family : win.theme.font.family
                                font.pixelSize: Math.round(13 * win.zoom)
                                color: win.theme.windowText
                                opacity: row.modelData.enabled ? 1 : 0.5
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                            Text {
                                text: win.modeLabel(row.modelData)
                                font.pixelSize: Math.round(12 * win.zoom)
                                color: win.theme.windowText
                                opacity: 0.6
                            }
                            KeyCap {
                                Layout.rightMargin: 4 * win.zoom
                                visible: row.modelData.name !== "" && row.modelData.key !== ""
                                opacity: row.modelData.enabled ? 1 : 0.5
                                text: "Space " + win.keyName(row.modelData.key)
                            }
                        }
                    }

                    Hint {
                        anchors.centerIn: parent
                        width: parent.width - 40 * win.zoom
                        visible: !shortcutList.count
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("No shortcuts yet: + makes one.")
                    }
                }
            }
        }

        ColumnLayout {
            spacing: 12 * win.zoom

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12 * win.zoom
                rowSpacing: 10 * win.zoom

                FormLabel {
                    text: qsTr("Name")
                }
                Field {
                    id: nameField

                    Layout.fillWidth: true
                    label: qsTr("Name")
                    placeholder: qsTr("Optional, like “Copy the path”")
                }

                FormLabel {
                    text: qsTr("Shortcut")
                }
                RowLayout {
                    spacing: 6 * win.zoom

                    KeyCap {
                        text: "Space"
                    }
                    // The key after Space, which a key typed here sets. None
                    // is fine: the shortcut then keeps its keys for later.
                    Rectangle {
                        id: keyBox

                        property string key

                        implicitWidth: Math.max(40 * win.zoom, keyText.implicitWidth + 16 * win.zoom)
                        implicitHeight: 26 * win.zoom
                        radius: 4 * win.zoom
                        color: win.theme.field
                        border.color: activeFocus ? win.theme.accent : win.theme.fieldBorder
                        activeFocusOnTab: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: qsTr("Key after Space")
                        Accessible.description: key
                        Keys.onPressed: event => win.typeKey(event)

                        Text {
                            id: keyText

                            anchors.centerIn: parent
                            text: keyBox.key ? win.keyName(keyBox.key) : qsTr("None")
                            font.family: keyBox.key ? win.theme.font.family : Application.font.family
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.theme.windowText
                            opacity: keyBox.key ? 1 : 0.5
                            textFormat: Text.PlainText
                        }
                        TapHandler {
                            onTapped: keyBox.forceActiveFocus()
                        }
                    }
                    Hint {
                        Layout.fillWidth: true
                        visible: keyBox.activeFocus
                        text: qsTr("Type a key (Backspace: none)")
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                    }
                }

                FormLabel {
                    text: qsTr("Runs")
                }
                Field {
                    id: macroField

                    Layout.fillWidth: true
                    label: qsTr("Keys it runs")
                    mono: true
                    rightRoom: macroButton.width + 4 * win.zoom
                    placeholder: Qt.platform.os === "osx" ? ":!echo %:p | pbcopy<CR>"
                        : Qt.platform.os === "windows" ? ":!echo %:p | clip<CR>" : ":!echo %:p<CR>"

                    WindowButton {
                        id: macroButton

                        anchors.right: parent.right
                        anchors.rightMargin: 2 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "M5 6.5 L8 9.5 L11 6.5"
                        tip: qsTr("Recorded Macros")
                        onClicked: macroList.visible ? macroList.close() : macroList.open()
                    }

                    // The registers q records into that hold something,
                    // in its own window, as Settings' font list.
                    T.Popup {
                        id: macroList

                        property var macros: []

                        y: macroField.height + 2 * win.zoom
                        width: macroField.width
                        height: Math.min(implicitContentHeight + topPadding + bottomPadding, 240 * win.zoom)
                        padding: 4 * win.zoom
                        popupType: Popup.Window
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                        onAboutToShow: macros = win.app.macroList()

                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.max(contentHeight, 24 * win.zoom)
                            model: macroList.macros
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollIndicator.vertical: ScrollIndicator {}

                            delegate: AbstractButton {
                                id: macro

                                required property var modelData

                                width: ListView.view.width
                                implicitHeight: 24 * win.zoom
                                focusPolicy: Qt.NoFocus
                                hoverEnabled: true
                                Accessible.name: "\"" + modelData.name + " " + modelData.keys
                                onClicked: {
                                    macroField.input.text = modelData.keys;
                                    macroList.close();
                                    macroField.input.forceActiveFocus();
                                }

                                background: Rectangle {
                                    radius: 3 * win.zoom
                                    color: macro.hovered ? win.theme.accent : "transparent"
                                }
                                // The register, dimmed, then its keys.
                                contentItem: Row {
                                    leftPadding: 4 * win.zoom
                                    rightPadding: 4 * win.zoom
                                    spacing: 10 * win.zoom

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "\"" + macro.modelData.name
                                        font.family: win.theme.font.family
                                        font.pixelSize: Math.round(13 * win.zoom)
                                        color: macro.hovered ? win.theme.highlightedText : win.theme.dim
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: macro.width - x - 4 * win.zoom
                                        text: macro.modelData.keys
                                        font.family: win.theme.font.family
                                        font.pixelSize: Math.round(13 * win.zoom)
                                        color: macro.hovered ? win.theme.highlightedText : win.theme.windowText
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                    }
                                }
                            }

                            Hint {
                                anchors.centerIn: parent
                                visible: !macroList.macros.length
                                text: qsTr("No macros recorded: qa records one in a, and q stops.")
                            }
                        }
                        background: Rectangle {
                            radius: 4 * win.zoom
                            color: win.theme.field
                            border.color: win.theme.fieldBorder
                        }
                    }
                }

                // One line, so the form is as tall before it's first laid
                // out (when the window's height is worked out) as after.
                Item {}
                Hint {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    text: qsTr("Keys as q records them, like <CR> for Enter and <Esc>.")
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }

                FormLabel {
                    text: qsTr("Mode")
                }
                Segmented {
                    id: modeChoice

                    theme: win.theme
                    options: win.modes
                    onPicked: index => current = index
                }

                Item {}
                AbstractButton {
                    id: enabledBox

                    checkable: true
                    focusPolicy: Qt.TabFocus
                    text: qsTr("Enabled")
                    Accessible.role: Accessible.CheckBox
                    Accessible.checked: checked

                    contentItem: Row {
                        spacing: 8 * win.zoom

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16 * win.zoom
                            height: 16 * win.zoom
                            radius: 3 * win.zoom
                            color: enabledBox.checked ? win.theme.accent : win.theme.field
                            border.color: enabledBox.checked || enabledBox.visualFocus ? win.theme.accent : win.theme.fieldBorder

                            Icon {
                                anchors.centerIn: parent
                                visible: enabledBox.checked
                                theme: win.theme
                                path: "M4 8.5 L7 11.5 L12 5"
                                color: win.theme.highlightedText
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: enabledBox.text
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.theme.windowText
                        }
                    }
                }
            }

            // Why it can't be saved, in room kept for two lines, so the
            // window doesn't change size.
            Hint {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.preferredHeight: Math.ceil(2 * problemMetrics.height)
                text: win.problem
                color: win.theme.error
                opacity: 1
                verticalAlignment: Text.AlignTop

                FontMetrics {
                    id: problemMetrics

                    font.pixelSize: Math.round(12 * win.zoom)
                }
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * win.zoom

                TextButton {
                    theme: win.theme
                    visible: win.editIndex >= 0
                    text: qsTr("Delete")
                    onClicked: win.remove()
                }
                Item {
                    Layout.fillWidth: true
                }
                TextButton {
                    theme: win.theme
                    text: qsTr("Cancel")
                    onClicked: win.showList(win.editIndex)
                }
                TextButton {
                    theme: win.theme
                    text: win.editIndex < 0 ? qsTr("Create") : qsTr("Save")
                    enabled: win.canSave
                    onClicked: win.save()
                }
            }
        }
    }
}
