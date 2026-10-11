pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Templates as T

// The user's shortcuts (Space q, Koil > Shortcuts…, or a button in
// Settings): each is Space and a key that run keys of theirs, as a macro
// does (see Vim.shortcuts), in normal mode, visual mode or both, with a
// name, and on or off. The list shows each by its name, else its key, else
// its keys. A click on one (or Enter) runs it in the main window, also one
// with no key (main.qml's runShortcut); its pencil shows all of it in a
// form, which Save saves, used at once (saveShortcuts), and + (or Cmd+N)
// does for a new one. The search over the list has the keys, and shows
// only the ones it matches: Up and Down pick one, and Enter runs it. Its keys can be typed or taken from a macro recorded (a
// register q records into). Tab goes through all of it (see tab).
Window {
    id: win

    // main.qml's window: the shortcuts, saveShortcuts, runShortcut, Koil's
    // own keys after Space (spaceKeys), the macros recorded (macroList),
    // and the names of keys in keys written out (keyParts).
    required property var app
    required property Theme theme

    readonly property real zoom: theme.zoom
    readonly property bool isMac: Qt.platform.os === "osx"
    // Whether this window has the keys, which its shortcuts are only for.
    // A Shortcut takes its window as active while any of the main
    // window's has the keys (Settings, or the main one): Esc there closed
    // this one, and with Settings open too, the two Escs were ambiguous,
    // so neither did anything.
    readonly property bool focused: activeFocusItem !== null
    readonly property var shortcuts: app.shortcuts
    readonly property var modes: [
        { label: qsTr("Normal"), value: "normal" },
        { label: qsTr("Visual"), value: "visual" },
        { label: qsTr("Both"), value: "both" }
    ]
    // The shortcuts the list shows, by their index: those the search
    // matches, every word of it (in any case) in the name or the keys, or
    // the key ("space c" matches Space c; a part of "space", like "pa",
    // doesn't match every shortcut with a key).
    readonly property var shown: {
        const words = searchField.input.text.toLowerCase().split(/\s+/).filter(w => w);
        return shortcuts.map((s, i) => i).filter(i => {
            const s = shortcuts[i];
            const text = (s.name + "\n" + s.macro).toLowerCase();
            return words.every(w => text.includes(w) || s.key && (w === "space" || w === s.key.toLowerCase()));
        });
    }
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
    // Keys written out (a shortcut's), as StyledText: the names of keys,
    // like <CR>, in `color` (the theme's for them, if not given), so they
    // stand out from the characters that type themselves.
    function styledKeys(keys, color) {
        const escape = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            .replace(/ /g, "&nbsp;");
        return app.keyParts(keys).map(p => p.special ? "<font color=\"" + (color || theme.specialKey) + "\">"
            + escape(p.text) + "</font>" : escape(p.text)).join("");
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
    // window the first time and whenever it was closed, and then on its
    // first shortcut, with no search, which has the keys: typing searches
    // at once.
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
            editing = false;
            searchField.input.text = "";
            shortcutList.currentIndex = shown.length ? 0 : -1;
        }
        show();
        raise();
        requestActivate();
        if (!editing)
            focusSearch();
    }
    // The keys to the search, with a shortcut picked if any is shown.
    function focusSearch(reason) {
        if (shortcutList.currentIndex < 0 && shortcutList.count)
            shortcutList.currentIndex = 0;
        searchField.input.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason);
    }
    // Tab and Shift+Tab: the keys to the next or previous of what the page
    // shown has, that's there and enabled. Qt's own Tab reaches only text
    // fields and lists on macOS, unless Keyboard navigation is on in
    // System Settings. From `from` if given, else from what has the keys.
    function tab(event, from) {
        const forward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier);
        const reason = forward ? Qt.TabFocusReason : Qt.BacktabFocusReason;
        const row = shortcutList.currentItem as ShortcutRow;
        const chain = (editing ? [nameField.input, keyBox, macroField.input, macroButton, modeChoice, enabledBox,
            deleteButton, cancelButton, saveButton] : [searchField.input, row ? row.editButton : null,
            row ? row.deleteButton : null, newButton]).filter(i => i && i.visible && i.enabled);
        const at = chain.indexOf(from || activeFocusItem);
        const next = chain[at < 0 ? (forward ? 0 : chain.length - 1) : (at + (forward ? 1 : chain.length - 1)) % chain.length];
        if (macroList.visible) {
            macroList.close();
            requestActivate();
        }
        if (next === searchField.input)
            focusSearch(reason);
        else if (next)
            next.forceActiveFocus(reason);
        event.accepted = true;
    }
    // Runs the shortcut at `index` in the main window, which this one
    // closes for.
    function run(index) {
        const s = shortcuts[index];
        close();
        app.runShortcut(s);
    }
    // Back to the list from the form, on the shortcut it showed (by its
    // index), if the search shows it.
    function showList(index) {
        editing = false;
        shortcutList.currentIndex = index === undefined ? -1 : shown.indexOf(index);
        focusSearch();
    }
    // The shortcut the list's current row shows, by its index; -1 if none.
    function currentShortcut() {
        return shortcutList.currentIndex < 0 ? -1 : shown[shortcutList.currentIndex];
    }
    // Esc: from the form back to the list; in the list, it empties the
    // search, as in a macOS search field, or with none, it closes.
    function back() {
        if (editing) {
            showList(editIndex);
        } else if (searchField.input.text) {
            searchField.input.text = "";
            focusSearch();
        } else {
            close();
        }
    }
    // The form for the shortcut at `index`, or for a new one (-1).
    function edit(index) {
        const s = index < 0 ? { name: "", key: "", macro: "", mode: "normal", enabled: true } : shortcuts[index];
        editIndex = index;
        nameField.input.text = s.name;
        keyBox.key = s.key;
        macroField.input.text = s.macro;
        // From its start, rather than scrolled to its end.
        macroField.input.cursorPosition = 0;
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
    function remove(index) {
        const row = shortcutList.currentIndex;
        app.saveShortcuts(shortcuts.filter((s, i) => i !== index));
        editing = false;
        shortcutList.currentIndex = Math.min(row, shown.length - 1);
        focusSearch();
    }
    // A key while the macros are listed, which the list's window gets
    // (else the button that shows them): Down and Up go through them,
    // Enter takes one, and Tab goes on from the button.
    function macroKey(event) {
        const last = macroList.macros.length - 1;
        if (event.key === Qt.Key_Down)
            macroList.highlighted = Math.min(last, macroList.highlighted + 1);
        else if (event.key === Qt.Key_Up)
            macroList.highlighted = Math.max(0, macroList.highlighted - 1);
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && macroList.highlighted >= 0)
            takeMacro(macroList.macros[macroList.highlighted]);
        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            tab(event, macroButton);
        else
            return;
        event.accepted = true;
    }
    // A macro picked from the list of them, as the keys to run.
    function takeMacro(macro) {
        macroField.input.text = macro.keys;
        macroList.close();
        // Back from the list's window, which some platforms leave active.
        requestActivate();
        macroField.input.forceActiveFocus();
    }
    // A key typed in the form's key box: the key after Space, any that
    // types a character (Backspace: none).
    function typeKey(event) {
        const typed = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier) ? "" : event.text;
        if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)
            keyBox.key = "";
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
        enabled: win.focused
        onActivated: win.close()
    }
    // Not while the macros are listed, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: win.focused && !macroList.visible
        onActivated: win.back()
    }
    Shortcut {
        sequences: [StandardKey.New]
        enabled: win.focused && !win.editing
        onActivated: win.edit(-1)
    }
    // In the form, Enter saves, whatever has the keys (Space clicks a
    // button), as Return does a macOS dialog's default button. Not while
    // the macros are listed, where it takes one (see macroKey).
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: win.focused && win.editing && !macroList.visible
        onActivated: win.save()
    }

    // A small button with an icon, which Tab reaches.
    component WindowButton: IconButton {
        theme: win.theme
        color: win.theme.windowText
        focusPolicy: Qt.TabFocus
        Keys.onTabPressed: event => win.tab(event)
        Keys.onBacktabPressed: event => win.tab(event)
    }

    component FormButton: TextButton {
        theme: win.theme
        Keys.onTabPressed: event => win.tab(event)
        Keys.onBacktabPressed: event => win.tab(event)
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

    // A text field.
    component Field: Rectangle {
        id: field

        property alias input: fieldInput
        property string label
        property string placeholder
        // Keys, in the editor's font.
        property bool mono
        // Room on the left for an icon, and on the right for a button.
        property real leftRoom: 8 * win.zoom
        property real rightRoom: 8 * win.zoom

        // A key, before the field types it, unless this takes it.
        signal keyPressed(var event)

        implicitWidth: 200 * win.zoom
        implicitHeight: 26 * win.zoom
        radius: 4 * win.zoom
        color: win.theme.field
        border.color: fieldInput.activeFocus ? win.theme.accent : win.theme.fieldBorder

        TextInput {
            id: fieldInput

            x: field.leftRoom
            width: field.width - x - field.rightRoom
            height: field.height
            clip: true
            font.family: field.mono ? win.theme.font.family : Application.font.family
            font.pixelSize: Math.round(13 * win.zoom)
            // Keys are drawn by `keysShown` over it, in colors.
            color: field.mono ? "transparent" : win.theme.windowText
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            selectionColor: win.theme.highlight
            selectedTextColor: field.mono ? "transparent" : win.theme.highlightedText
            // Qt's own cursor has the text's color, which is clear for keys.
            // Like it, this one blinks (but stays while it moves), and like
            // macOS's, it hides while text is selected.
            cursorDelegate: Rectangle {
                id: caret

                width: fieldInput.cursorRectangle.width
                color: win.theme.windowText
                visible: fieldInput.activeFocus && fieldInput.selectionStart === fieldInput.selectionEnd

                Timer {
                    id: blink

                    interval: Qt.styleHints.cursorFlashTime / 2
                    running: caret.visible && interval > 0
                    repeat: true
                    onTriggered: caret.opacity = caret.opacity ? 0 : 1
                    onRunningChanged: caret.opacity = 1
                }
                Connections {
                    target: fieldInput

                    function onCursorPositionChanged() {
                        caret.opacity = 1;
                        blink.restart();
                    }
                }
            }
            Accessible.name: field.label
            Keys.onPressed: event => field.keyPressed(event)
            Keys.onTabPressed: event => win.tab(event)
            Keys.onBacktabPressed: event => win.tab(event)

            // The keys typed, with their names colored (see styledKeys),
            // where the field shows its text, as it scrolls sideways: the
            // cursor's place, less the text before it (a font of one
            // width, so the colors don't move the characters).
            Text {
                id: keysShown

                x: fieldInput.cursorRectangle.x - beforeCursor.advanceWidth
                height: fieldInput.height
                visible: field.mono
                text: field.mono ? win.styledKeys(fieldInput.text) : ""
                textFormat: Text.StyledText
                font: fieldInput.font
                color: win.theme.windowText
                verticalAlignment: Text.AlignVCenter

                TextMetrics {
                    id: beforeCursor

                    font: fieldInput.font
                    text: fieldInput.text.slice(0, fieldInput.cursorPosition)
                }
            }
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

    // A shortcut in the list: a click runs it, as Enter does while it's the
    // current one, and its buttons edit or delete it.
    component ShortcutRow: AbstractButton {
        id: row

        // { at, shortcut }: the shortcut, and its index (see shown). It
        // comes with it, as the shortcuts change before the list does.
        required property var modelData
        readonly property int at: modelData.at
        readonly property var shortcut: modelData.shortcut
        readonly property Item editButton: editIcon
        readonly property Item deleteButton: deleteIcon
        // Highlighted while the keys are in the search, where Up and Down
        // move it and Enter runs it, or on its buttons.
        readonly property bool current: row.ListView.isCurrentItem
            && (searchField.input.activeFocus || editIcon.activeFocus || deleteIcon.activeFocus)

        width: ListView.view.width
        implicitHeight: 30 * win.zoom
        focusPolicy: Qt.NoFocus
        hoverEnabled: true
        Accessible.name: win.titleOf(shortcut)
        Accessible.description: qsTr("Runs it")
        onClicked: win.run(at)

        background: Rectangle {
            radius: 3 * win.zoom
            color: row.current ? win.theme.checked : row.hovered ? win.theme.hover : "transparent"
        }
        contentItem: RowLayout {
            spacing: 8 * win.zoom

            Text {
                Layout.fillWidth: true
                leftPadding: 6 * win.zoom
                // Keys (it has no name) in the editor's font, and with
                // neither a name nor a key, its keys, colored.
                readonly property bool showsKeys: !row.shortcut.name && !row.shortcut.key
                text: showsKeys ? win.styledKeys(row.shortcut.macro) : win.titleOf(row.shortcut)
                font.family: row.shortcut.name ? Application.font.family : win.theme.font.family
                font.pixelSize: Math.round(13 * win.zoom)
                color: win.theme.windowText
                opacity: row.shortcut.enabled ? 1 : 0.5
                elide: Text.ElideRight
                textFormat: showsKeys ? Text.StyledText : Text.PlainText
            }
            Text {
                text: win.modeLabel(row.shortcut)
                font.pixelSize: Math.round(12 * win.zoom)
                color: win.theme.windowText
                opacity: 0.6
            }
            KeyCap {
                visible: row.shortcut.name !== "" && row.shortcut.key !== ""
                opacity: row.shortcut.enabled ? 1 : 0.5
                text: "Space " + win.keyName(row.shortcut.key)
            }
            WindowButton {
                id: editIcon

                iconPath: "M10.5 3 L13 5.5 L6 12.5 L3 13 L3.5 10 Z M9 4.5 L11.5 7"
                tip: qsTr("Edit")
                onClicked: win.edit(row.at)
            }
            WindowButton {
                id: deleteIcon

                Layout.rightMargin: 2 * win.zoom
                iconPath: "M3 4.5 H13 M6.5 4.5 V3 H9.5 V4.5 M4.5 4.5 L5.2 13 H10.8 L11.5 4.5 M6.8 7 V11 M9.2 7 V11"
                tip: qsTr("Delete")
                onClicked: win.remove(row.at)
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

                // It has the keys: Up and Down pick a shortcut, Enter runs
                // it, and Esc empties it (see back).
                Field {
                    id: searchField

                    Layout.fillWidth: true
                    label: qsTr("Search shortcuts")
                    placeholder: qsTr("Search")
                    leftRoom: searchIcon.width + 8 * win.zoom

                    Icon {
                        id: searchIcon

                        x: 5 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        theme: win.theme
                        path: "M3 7 A4 4 0 1 0 11 7 A4 4 0 1 0 3 7 Z M10 10 L13.5 13.5"
                        color: win.theme.windowText
                        opacity: 0.6
                    }

                    Connections {
                        target: searchField.input

                        function onTextChanged() {
                            shortcutList.currentIndex = win.shown.length ? 0 : -1;
                        }
                    }
                    onKeyPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (shortcutList.currentIndex >= 0)
                                win.run(win.currentShortcut());
                        } else if (event.key === Qt.Key_Down)
                            shortcutList.incrementCurrentIndex();
                        else if (event.key === Qt.Key_Up)
                            shortcutList.decrementCurrentIndex();
                        else
                            return;
                        event.accepted = true;
                    }
                }
                WindowButton {
                    id: newButton

                    iconPath: "M4 8 H12 M8 4 V12"
                    tip: qsTr("New Shortcut")
                    shortcuts: [win.isMac ? "⌘N" : "Ctrl+N"]
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
                    model: win.shown.map(i => ({ at: i, shortcut: win.shortcuts[i] }))
                    currentIndex: -1
                    boundsBehavior: Flickable.StopAtBounds
                    Accessible.name: qsTr("Shortcuts")
                    ScrollIndicator.vertical: ScrollIndicator {}

                    // Picked from the search, which keeps the keys.
                    delegate: ShortcutRow {}

                    Hint {
                        anchors.centerIn: parent
                        width: parent.width - 40 * win.zoom
                        visible: !shortcutList.count
                        horizontalAlignment: Text.AlignHCenter
                        text: win.shortcuts.length ? qsTr("No shortcut matches “%1”.").arg(searchField.input.text.trim())
                            : qsTr("No shortcuts yet: + makes one.")
                    }
                }
            }

            Hint {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: qsTr("↑ and ↓ pick one, and Enter or a click runs it.")
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
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
                        Keys.onTabPressed: event => win.tab(event)
                        Keys.onBacktabPressed: event => win.tab(event)

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
                        Keys.onPressed: event => {
                            if (macroList.visible)
                                win.macroKey(event);
                        }
                    }

                    // The registers q records into that hold something,
                    // in its own window, as Settings' font list.
                    T.Popup {
                        id: macroList

                        property var macros: []
                        // The one Enter takes.
                        property int highlighted: -1

                        y: macroField.height + 2 * win.zoom
                        width: macroField.width
                        height: Math.min(implicitContentHeight + topPadding + bottomPadding, 240 * win.zoom)
                        padding: 4 * win.zoom
                        popupType: Popup.Window
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                        // Its window gets the keys while it's open (see
                        // macroKey).
                        focus: true
                        onAboutToShow: {
                            macros = win.app.macroList();
                            highlighted = macros.length ? 0 : -1;
                        }
                        onHighlightedChanged: {
                            if (highlighted >= 0)
                                macroView.positionViewAtIndex(highlighted, ListView.Contain);
                        }

                        contentItem: ListView {
                            id: macroView

                            focus: true
                            clip: true
                            Keys.onPressed: event => win.macroKey(event)
                            implicitHeight: Math.max(contentHeight, 24 * win.zoom)
                            model: macroList.macros
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollIndicator.vertical: ScrollIndicator {}

                            delegate: AbstractButton {
                                id: macro

                                required property var modelData
                                required property int index
                                readonly property bool highlighted: macroList.highlighted === index

                                width: ListView.view.width
                                implicitHeight: 24 * win.zoom
                                focusPolicy: Qt.NoFocus
                                hoverEnabled: true
                                Accessible.name: "\"" + modelData.name + " " + modelData.keys
                                onHoveredChanged: if (hovered) macroList.highlighted = index
                                onClicked: win.takeMacro(modelData)

                                background: Rectangle {
                                    radius: 3 * win.zoom
                                    color: macro.highlighted ? win.theme.accent : "transparent"
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
                                        color: macro.highlighted ? win.theme.highlightedText : win.theme.dim
                                        textFormat: Text.PlainText
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: macro.width - x - 4 * win.zoom
                                        text: win.styledKeys(macro.modelData.keys, macro.highlighted
                                            ? win.theme.highlightedText : undefined)
                                        font.family: win.theme.font.family
                                        font.pixelSize: Math.round(13 * win.zoom)
                                        color: macro.highlighted ? win.theme.highlightedText : win.theme.windowText
                                        elide: Text.ElideRight
                                        textFormat: Text.StyledText
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
                    Accessible.name: qsTr("Mode")
                    onPicked: index => current = index
                    Keys.onTabPressed: event => win.tab(event)
                    Keys.onBacktabPressed: event => win.tab(event)
                }

                Item {}
                AbstractButton {
                    id: enabledBox

                    checkable: true
                    focusPolicy: Qt.TabFocus
                    text: qsTr("Enabled")
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: text
                    Accessible.checked: checked
                    Keys.onTabPressed: event => win.tab(event)
                    Keys.onBacktabPressed: event => win.tab(event)
                    Keys.onReturnPressed: click()
                    Keys.onEnterPressed: click()

                    // Its ring, as the box is the accent's color when on.
                    background: Rectangle {
                        x: -4 * win.zoom
                        y: -3 * win.zoom
                        width: parent.width + 8 * win.zoom
                        height: parent.height + 6 * win.zoom
                        radius: 4 * win.zoom
                        color: "transparent"
                        border.color: enabledBox.visualFocus ? win.theme.accent : "transparent"
                    }

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

                FormButton {
                    id: deleteButton

                    visible: win.editIndex >= 0
                    text: qsTr("Delete")
                    onClicked: win.remove(win.editIndex)
                }
                Item {
                    Layout.fillWidth: true
                }
                FormButton {
                    id: cancelButton

                    text: qsTr("Cancel")
                    onClicked: win.showList(win.editIndex)
                }
                FormButton {
                    id: saveButton

                    primary: true
                    text: win.editIndex < 0 ? qsTr("Create") : qsTr("Save")
                    enabled: win.canSave
                    onClicked: win.save()
                }
            }
        }
    }
}
