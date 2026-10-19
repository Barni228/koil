pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Templates as T

// The Settings window (Cmd+,): font, font size, line numbers, syntax
// colors, word wrap, theme, whether folders come first, when applying asks
// first, the dir Koil starts in, and the shell :! runs commands in; and on
// macOS, the
// shortcut that opens the folder selected in Finder, which System Settings
// changes, the `koil` command, which it installs, and whether :! gets the
// environment read from the user's shell. It
// shows the saved settings, which Koil starts with; changes here are saved
// and apply at once (app.changeSetting), but the dir only at the next start.
// The zoom and :set change only the settings in use, so they don't show
// here. Each setting has a button that
// resets it to its default, and Restore Defaults resets them all. The
// settings scroll past a height (maxListHeight), and the pointer on one
// shows what it does (its label's `about`), so the notes under some of
// them are short.
Window {
    id: win

    // main.qml's window: the defaults, the fonts, the shells,
    // changeSetting.
    required property var app
    // The saved settings: fontSize, fontFamily, number, relativeNumber,
    // syntax, wrap, colorScheme, dirsFirst, confirmChanges, startDir, shell,
    // shellEnvironment.
    required property var settings
    required property Theme theme
    // main.qml's Document, for the folder picked (a var, so this file needs
    // no `import Koil`).
    required property var document

    readonly property real zoom: theme.zoom
    readonly property color textColor: theme.windowText
    readonly property color accent: theme.accent
    readonly property color borderColor: theme.fieldBorder

    // Line numbers as one choice: :set nonu nornu, nu, rnu, or both.
    readonly property var lineNumberModes: [
        { label: qsTr("Off"), number: false, relative: false },
        { label: qsTr("On"), number: true, relative: false },
        { label: qsTr("Relative"), number: false, relative: true },
        { label: qsTr("Hybrid"), number: true, relative: true }
    ]
    readonly property int lineNumberMode: lineNumberModes.findIndex(
        m => m.number === settings.number && m.relative === settings.relativeNumber)
    // Files' colors (:set syntax), on or off.
    readonly property var syntaxModes: [
        { label: qsTr("On"), value: true },
        { label: qsTr("Off"), value: false }
    ]
    // Long lines (:set wrap), wrapped or not.
    readonly property var wrapModes: [
        { label: qsTr("Off"), value: false },
        { label: qsTr("On"), value: true }
    ]
    // The listing's dirs before its files (:set dirsfirst), or sorted with
    // them.
    readonly property var dirsFirstModes: [
        { label: qsTr("On"), value: true },
        { label: qsTr("Off"), value: false }
    ]
    readonly property var colorSchemes: [
        { label: qsTr("System"), value: "system" },
        { label: qsTr("Light"), value: "light" },
        { label: qsTr("Dark"), value: "dark" }
    ]
    // When applying the listing's changes (or creating a file) asks first.
    readonly property var confirmModes: [
        { label: qsTr("Always"), value: "always" },
        { label: qsTr("When deleting"), value: "deleting" },
        { label: qsTr("Never"), value: "never" }
    ]
    // Whether :! gets the environment read from the user's shell.
    readonly property var shellEnvironmentModes: [
        { label: qsTr("On"), value: true },
        { label: qsTr("Off"), value: false }
    ]

    // The shortcut of "Open in Koil", the macOS service (see
    // Document.finderServiceShortcut), read again whenever this window is
    // active, as System Settings changes it.
    property string finderShortcut: ""
    // What's where the `koil` command goes (Document.commandStatus), read
    // again whenever this window is active, and once it's installed or
    // removed (changingCommand until then); and why that failed, if it did.
    property string commandStatus: ""
    property bool changingCommand: false
    property string commandError: ""

    readonly property bool customFontFamily: settings.fontFamily !== app.defaultFontFamily
    readonly property bool customFontSize: settings.fontSize !== app.defaultFontSize
    readonly property bool customLineNumbers: lineNumberMode !== 0
    readonly property bool customSyntax: !settings.syntax
    readonly property bool customWrap: settings.wrap
    readonly property bool customColorScheme: settings.colorScheme !== "system"
    readonly property bool customDirsFirst: !settings.dirsFirst
    readonly property bool customConfirm: settings.confirmChanges !== "always"
    readonly property bool customStartDir: settings.startDir !== ""
    readonly property bool customShell: settings.shell !== ""
    readonly property bool customShellEnvironment: !settings.shellEnvironment

    // How tall the settings get before they scroll: about half of them at
    // a time, and never past the screen.
    readonly property real maxListHeight: Math.min(Math.round(440 * zoom), Math.max(200, Screen.desktopAvailableHeight - 200))
    readonly property bool scrolls: grid.implicitHeight > maxListHeight
    // Room for the scroll bar, right of the reset buttons.
    readonly property real barRoom: 14 * zoom
    // The setting whose tip shows (see settingAt), and how many buttons
    // with tips of their own the pointer is on.
    property var tipSetting: null
    property int buttonsHovered: 0

    function scrollTo(y) {
        scroller.contentY = Math.max(0, Math.min(scroller.maxY, y));
    }
    // The setting at `y` in the grid: { label, top, bottom } of its row
    // (its label's, which has its `about`), as far down as the note under
    // it goes. GridLayout puts the children that show three to a row.
    function settingAt(y) {
        const shown = [];
        for (const child of grid.children) {
            if (child.visible)
                shown.push(child);
        }
        const half = grid.rowSpacing / 2;
        let setting = null;
        for (let i = 0; i + 2 < shown.length; i += 3) {
            const row = shown.slice(i, i + 3);
            const top = Math.min(...row.map(c => c.y)) - half;
            const bottom = Math.max(...row.map(c => c.y + c.height)) + half;
            if (row[0].about !== undefined)
                setting = { label: row[0], top: top, bottom: bottom - half, end: bottom };
            else if (setting)
                setting.end = bottom;
            if (setting && y >= setting.top && y < setting.end)
                return { label: setting.label, top: setting.top + half, bottom: setting.bottom };
        }
        return null;
    }
    // Whether `item` is in the settings (not the buttons under them).
    function inGrid(item) {
        for (let i = item; i; i = i.parent) {
            if (i === grid)
                return true;
        }
        return false;
    }

    // Tab scrolls to what it goes to.
    onActiveFocusItemChanged: {
        const item = activeFocusItem;
        if (!item || !inGrid(item))
            return;
        const top = item.mapToItem(grid, 0, 0).y, margin = 8 * zoom;
        if (top - margin < scroller.contentY)
            scrollTo(top - margin);
        else if (top + item.height + margin > scroller.contentY + scroller.height)
            scrollTo(top + item.height + margin - scroller.height);
    }

    function setFontSize(size) {
        app.changeSetting("fontSize", Math.max(app.minFontSize, Math.min(app.maxFontSize, size)));
    }
    function setLineNumberMode(i) {
        app.changeSetting("number", lineNumberModes[i].number);
        app.changeSetting("relativeNumber", lineNumberModes[i].relative);
    }
    // What the Command line row says under its button.
    function commandNote() {
        if (commandError)
            return commandError;
        if (commandStatus === "installed")
            return qsTr("Installed: `koil` in a terminal opens Koil.");
        if (commandStatus === "otherKoil")
            return qsTr("`koil` opens another copy of Koil, or one that moved.");
        if (commandStatus === "other")
            return qsTr("`/usr/local/bin/koil` is another program.");
        return qsTr("Lets `koil` in a terminal open Koil.");
    }
    function restoreDefaults() {
        app.changeSetting("fontFamily", app.defaultFontFamily);
        setFontSize(app.defaultFontSize);
        setLineNumberMode(0);
        app.changeSetting("syntax", true);
        app.changeSetting("wrap", false);
        app.changeSetting("colorScheme", "system");
        app.changeSetting("dirsFirst", true);
        app.changeSetting("confirmChanges", "always");
        settings.startDir = "";
        app.changeSetting("shell", "");
        app.changeSetting("shellEnvironment", true);
    }

    // Shows the window, centered near the top of the main window the first
    // time and whenever it was closed. It opens with no field focused or
    // selected (a closed window keeps its focus item, which would get the
    // keys again, and the field its selection).
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
            scroller.contentY = 0;
            fontSearch.focus = false;
            fontSearch.deselect();
            sizeInput.focus = false;
            sizeInput.deselect();
            startInput.focus = false;
            startInput.deselect();
            shellInput.focus = false;
            shellInput.deselect();
        }
        show();
        raise();
        requestActivate();
    }

    onActiveChanged: {
        if (active && app.isMac) {
            finderShortcut = document.finderServiceShortcut();
            commandStatus = document.commandStatus();
        }
    }

    Connections {
        target: win.document

        function onCommandChanged(error) {
            win.changingCommand = false;
            win.commandError = error;
            win.commandStatus = win.document.commandStatus();
        }
    }

    title: qsTr("Settings")
    flags: Qt.Dialog
    color: theme.window
    // Its size follows the zoom, so it isn't resizable.
    readonly property int fitWidth: Math.ceil(content.implicitWidth + 2 * content.x)
    readonly property int fitHeight: Math.ceil(content.implicitHeight + 2 * content.y)

    width: fitWidth
    height: fitHeight
    minimumWidth: fitWidth
    maximumWidth: fitWidth
    minimumHeight: fitHeight
    maximumHeight: fitHeight

    // Only while this window has the keys: a Shortcut takes its window as
    // active while any of the main window's has them (see
    // ShortcutsWindow.focused).
    Shortcut {
        sequences: [StandardKey.Close]
        enabled: win.activeFocusItem !== null
        onActivated: win.close()
    }
    // Not while the font or shell list is open, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: win.activeFocusItem !== null && !fontList.visible && !shellList.visible
        onActivated: win.close()
    }

    // A small button with an icon, which Tab reaches. Its tip shows in
    // place of its setting's.
    component SettingButton: IconButton {
        theme: win.theme
        color: win.textColor
        focusPolicy: Qt.TabFocus
        onHoveredChanged: win.buttonsHovered += hovered ? 1 : -1
    }

    // Resets one setting; hidden while it has its default value.
    component ResetButton: SettingButton {
        iconPath: "M6 3 L3 6 L6 9 M3 6 H10 A3 3 0 0 1 10 12 H7"
        tip: qsTr("Reset to Default")
        opacity: enabled ? 1 : 0
    }

    // A setting's name, and in `about`, what it does, which shows with the
    // pointer anywhere on its row (see settingAt).
    component SettingLabel: Label {
        property string about

        font.pixelSize: Math.round(13 * win.zoom)
        color: win.textColor
    }

    ColumnLayout {
        id: content

        x: 20 * win.zoom
        y: 16 * win.zoom
        spacing: 16 * win.zoom

        // The settings, which scroll past maxListHeight. Not interactive,
        // since a drag selects text in a field; the wheel scrolls it.
        Flickable {
            id: scroller

            readonly property real maxY: Math.max(0, contentHeight - height)

            Layout.preferredWidth: grid.implicitWidth + (win.scrolls ? win.barRoom : 0)
            Layout.preferredHeight: Math.min(grid.implicitHeight, win.maxListHeight)
            contentWidth: width
            contentHeight: grid.implicitHeight
            clip: true
            interactive: false
            // The tip would stay where its setting was.
            onContentYChanged: win.tipSetting = null

            ScrollBar.vertical: ScrollBar {}

            // The trackpad too, which a WheelHandler leaves out by default.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => win.scrollTo(scroller.contentY - (event.pixelDelta.y || event.angleDelta.y / 120 * 60 * win.zoom))
            }

            // Under the setting's row, or over it if there's no room in
            // view; not while a button's own tip shows.
            Tip {
                readonly property var at: win.tipSetting
                readonly property real below: at ? at.bottom + 4 * win.zoom : 0

                parent: grid
                theme: win.theme
                wrapWidth: 340 * win.zoom
                closePolicy: Popup.NoAutoClose
                visible: at !== null && win.buttonsHovered === 0
                text: at ? at.label.about : ""
                x: at ? at.label.x : 0
                y: !at ? 0 : below + height <= scroller.contentY + scroller.height ? below
                    : at.top - height - 4 * win.zoom
            }

            GridLayout {
                id: grid

                columns: 3
                columnSpacing: 12 * win.zoom
                rowSpacing: 10 * win.zoom

                // The setting under the pointer, wherever it is in its row,
                // shows what it does (see settingAt). A HoverHandler, as it
                // takes the hover along with the controls.
                HoverHandler {
                    onPointChanged: {
                        const found = hovered ? win.settingAt(point.position.y) : null;
                        if (found?.label !== win.tipSetting?.label)
                            win.tipSetting = found;
                    }
                    onHoveredChanged: {
                        if (!hovered)
                            win.tipSetting = null;
                    }
                }

                SettingLabel {
                    text: qsTr("Font")
                    about: qsTr("The editor's font. Only monospaced fonts are listed, as Koil lines text up in columns. Type in the field to search them.")
                }
                // The installed monospaced fonts, each shown in itself. Typing in
                // the field searches them (for every word, in any case); Up/Down
                // and Return pick one, and Esc goes back to the font in use.
                Rectangle {
                    id: fontPicker

                    // The fonts in the list, and the one Return picks.
                    property var matches: []
                    property int highlighted: -1
                    // Whether the field holds a search rather than the font in use.
                    property bool searching: false

                    function showList() {
                        win.app.loadFontFamilies();
                        matches = win.app.fontFamilies;
                        highlighted = matches.indexOf(win.settings.fontFamily);
                        fontList.open();
                        fontListView.positionViewAtIndex(Math.max(0, highlighted), ListView.Center);
                    }
                    function search(query) {
                        win.app.loadFontFamilies();
                        const words = query.toLowerCase().split(/\s+/).filter(w => w);
                        matches = win.app.fontFamilies.filter(f => words.every(w => f.toLowerCase().includes(w)));
                        highlighted = matches.length ? 0 : -1;
                        searching = true;
                        fontList.open();
                        fontListView.positionViewAtBeginning();
                    }
                    function move(step) {
                        if (!fontList.visible) {
                            showList();
                        } else if (matches.length) {
                            highlighted = Math.max(0, Math.min(matches.length - 1, highlighted + step));
                            fontListView.positionViewAtIndex(highlighted, ListView.Contain);
                        }
                    }
                    // Return: picks the highlighted font, or shows the list.
                    function accept() {
                        if (fontList.visible)
                            finish(matches[highlighted]);
                        else
                            showList();
                    }
                    // Closes the list, after picking `family` if given.
                    function finish(family) {
                        if (family)
                            win.app.changeSetting("fontFamily", family);
                        fontList.close();
                    }

                    Layout.fillWidth: true
                    implicitWidth: 180 * win.zoom
                    implicitHeight: 26 * win.zoom
                    radius: 4 * win.zoom
                    color: win.theme.field
                    border.color: fontSearch.activeFocus ? win.accent : win.borderColor

                    TextInput {
                        id: fontSearch

                        x: 8 * win.zoom
                        width: parent.width - x - fontButton.width - 2 * win.zoom
                        height: parent.height
                        clip: true
                        text: win.settings.fontFamily
                        font.family: fontPicker.searching ? Application.font.family : win.settings.fontFamily
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: win.textColor
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        selectionColor: win.theme.highlight
                        selectedTextColor: win.theme.highlightedText
                        Accessible.name: qsTr("Font")

                        // Selects the whole name with the cursor at its start, so
                        // the field shows the start of a long one.
                        function selectFromStart() {
                            select(text.length, 0);
                        }

                        onTextEdited: fontPicker.search(text)
                        // Setting the text puts the cursor at its end, which the
                        // field scrolls to; a long name shows its start instead.
                        // (An edit always changes the text, so this skips typing.)
                        onTextChanged: {
                            if (!fontPicker.searching && text === win.settings.fontFamily)
                                cursorPosition = 0;
                        }
                        Component.onCompleted: cursorPosition = 0
                        onActiveFocusChanged: {
                            if (activeFocus)
                                fontSearch.selectFromStart();
                            else
                                fontPicker.finish();
                        }
                        Keys.onUpPressed: fontPicker.move(-1)
                        Keys.onDownPressed: fontPicker.move(1)
                        Keys.onReturnPressed: fontPicker.accept()
                        Keys.onEnterPressed: fontPicker.accept()
                        // Without the list, Esc closes the window.

                        // A click (not one in a search) shows the list and selects
                        // the name, so typing replaces it.
                        TapHandler {
                            onTapped: {
                                if (!fontList.visible) {
                                    fontPicker.showList();
                                    fontSearch.selectFromStart();
                                }
                            }
                        }

                        Text {
                            anchors.fill: parent
                            visible: fontPicker.searching && !fontSearch.text
                            text: qsTr("Search fonts")
                            font: fontSearch.font
                            color: win.textColor
                            opacity: 0.5
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    SettingButton {
                        id: fontButton

                        anchors.right: parent.right
                        anchors.rightMargin: 2 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "M5 6.5 L8 9.5 L11 6.5"
                        tip: qsTr("Show Fonts")
                        onClicked: {
                            if (fontList.visible) {
                                fontPicker.finish();
                            } else {
                                fontSearch.forceActiveFocus();
                                fontPicker.showList();
                            }
                        }
                    }

                    // Its own window, so the list isn't cut off by this one. The
                    // field keeps the keys, except Esc, which the popup takes.
                    T.Popup {
                        id: fontList

                        y: fontPicker.height + 2 * win.zoom
                        width: fontPicker.width
                        height: Math.min(implicitContentHeight + topPadding + bottomPadding, 320 * win.zoom)
                        padding: 4 * win.zoom
                        popupType: Popup.Window
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                        onClosed: {
                            fontPicker.searching = false;
                            fontSearch.text = Qt.binding(() => win.settings.fontFamily);
                        }

                        contentItem: ListView {
                            id: fontListView

                            clip: true
                            implicitHeight: Math.max(contentHeight, 24 * win.zoom)
                            model: fontPicker.matches
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollIndicator.vertical: ScrollIndicator {}

                            delegate: AbstractButton {
                                id: fontOption

                                required property string modelData
                                required property int index
                                readonly property bool highlighted: fontPicker.highlighted === index

                                width: ListView.view.width
                                implicitHeight: 24 * win.zoom
                                focusPolicy: Qt.NoFocus
                                hoverEnabled: true
                                Accessible.name: modelData
                                onHoveredChanged: if (hovered) fontPicker.highlighted = index
                                onClicked: fontPicker.finish(modelData)

                                background: Rectangle {
                                    radius: 3 * win.zoom
                                    color: fontOption.highlighted ? win.accent : "transparent"
                                }
                                contentItem: Text {
                                    leftPadding: 4 * win.zoom
                                    rightPadding: 4 * win.zoom
                                    text: fontOption.modelData
                                    font.family: fontOption.modelData
                                    font.pixelSize: Math.round(13 * win.zoom)
                                    color: fontOption.highlighted ? win.theme.highlightedText : win.textColor
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !fontPicker.matches.length
                                text: qsTr("No matching fonts")
                                font.pixelSize: Math.round(13 * win.zoom)
                                color: win.textColor
                                opacity: 0.6
                            }
                        }
                        background: Rectangle {
                            radius: 4 * win.zoom
                            color: win.theme.field
                            border.color: win.borderColor
                        }
                    }
                }
                ResetButton {
                    enabled: win.customFontFamily
                    onClicked: win.app.changeSetting("fontFamily", win.app.defaultFontFamily)
                }

                SettingLabel {
                    text: qsTr("Font size")
                    about: qsTr("The size of the editor's text, which everything else in Koil follows. View > Zoom In and Zoom Out change it until Koil quits, and Actual Size goes back to this.")
                }
                // − size +, where the size can also be typed.
                Rectangle {
                    implicitWidth: sizeRow.implicitWidth + 4 * win.zoom
                    implicitHeight: 26 * win.zoom
                    radius: 4 * win.zoom
                    color: win.theme.field
                    border.color: sizeInput.activeFocus ? win.accent : win.borderColor

                    Row {
                        id: sizeRow

                        anchors.centerIn: parent

                        SettingButton {
                            iconPath: "M4 8 H12"
                            tip: qsTr("Smaller")
                            enabled: win.settings.fontSize > win.app.minFontSize
                            onClicked: win.setFontSize(win.settings.fontSize - 1)
                        }
                        TextInput {
                            id: sizeInput

                            width: 36 * win.zoom
                            height: 22 * win.zoom
                            text: win.settings.fontSize
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.textColor
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            selectByMouse: true
                            selectionColor: win.theme.highlight
                            selectedTextColor: win.theme.highlightedText
                            validator: IntValidator {
                                bottom: 1
                                top: 999
                            }
                            Accessible.name: qsTr("Font size")
                            onActiveFocusChanged: if (activeFocus) selectAll()
                            onEditingFinished: {
                                const size = parseInt(text);
                                if (!isNaN(size))
                                    win.setFontSize(size);
                                text = Qt.binding(() => win.settings.fontSize);
                            }
                        }
                        SettingButton {
                            iconPath: "M4 8 H12 M8 4 V12"
                            tip: qsTr("Larger")
                            enabled: win.settings.fontSize < win.app.maxFontSize
                            onClicked: win.setFontSize(win.settings.fontSize + 1)
                        }
                    }
                }
                ResetButton {
                    enabled: win.customFontSize
                    onClicked: win.setFontSize(win.app.defaultFontSize)
                }

                SettingLabel {
                    text: qsTr("Line numbers")
                    about: qsTr("Numbers before the lines. On numbers them from the top, Relative counts from the cursor's line, and Hybrid does both, with the cursor's line's own number. `:set number` and `:set relativenumber` change it until Koil quits.")
                }
                Segmented {
                    theme: win.theme
                    options: win.lineNumberModes
                    current: win.lineNumberMode
                    onPicked: index => win.setLineNumberMode(index)
                }
                ResetButton {
                    enabled: win.customLineNumbers
                    onClicked: win.setLineNumberMode(0)
                }

                SettingLabel {
                    text: qsTr("Syntax colors")
                    about: qsTr("Colors the strings, numbers, comments, URLs and paths of files and the scratchpad, whatever their language. `:syntax off` turns it off until Koil quits.")
                }
                Segmented {
                    theme: win.theme
                    options: win.syntaxModes
                    current: win.syntaxModes.findIndex(m => m.value === win.settings.syntax)
                    onPicked: index => win.app.changeSetting("syntax", win.syntaxModes[index].value)
                }
                ResetButton {
                    enabled: win.customSyntax
                    onClicked: win.app.changeSetting("syntax", true)
                }

                SettingLabel {
                    text: qsTr("Word wrap")
                    about: qsTr("Long lines go on in rows under them, rather than past the window's edge. View > Word Wrap and `:set wrap` change it until Koil quits.")
                }
                Segmented {
                    theme: win.theme
                    options: win.wrapModes
                    current: win.wrapModes.findIndex(m => m.value === win.settings.wrap)
                    onPicked: index => win.app.changeSetting("wrap", win.wrapModes[index].value)
                }
                ResetButton {
                    enabled: win.customWrap
                    onClicked: win.app.changeSetting("wrap", false)
                }

                SettingLabel {
                    text: qsTr("Theme")
                    about: qsTr("Light or dark, or as the system is.")
                }
                Segmented {
                    theme: win.theme
                    options: win.colorSchemes
                    current: win.colorSchemes.findIndex(t => t.value === win.settings.colorScheme)
                    onPicked: index => win.app.changeSetting("colorScheme", win.colorSchemes[index].value)
                }
                ResetButton {
                    enabled: win.customColorScheme
                    onClicked: win.app.changeSetting("colorScheme", "system")
                }

                SettingLabel {
                    text: qsTr("Folders first")
                    about: qsTr("Lists folders before files; off, they're sorted together. `:set dirsfirst` changes it until Koil quits.")
                }
                Segmented {
                    theme: win.theme
                    options: win.dirsFirstModes
                    current: win.dirsFirstModes.findIndex(m => m.value === win.settings.dirsFirst)
                    onPicked: index => win.app.changeSetting("dirsFirst", win.dirsFirstModes[index].value)
                }
                ResetButton {
                    enabled: win.customDirsFirst
                    onClicked: win.app.changeSetting("dirsFirst", true)
                }

                SettingLabel {
                    text: qsTr("Ask before applying")
                    about: qsTr("Whether applying the listing's changes (`Space Space`) lists them for you to confirm first: always, only when something would be deleted, or never. `Space a` always asks.")
                }
                Segmented {
                    theme: win.theme
                    options: win.confirmModes
                    current: win.confirmModes.findIndex(m => m.value === win.settings.confirmChanges)
                    onPicked: index => win.app.changeSetting("confirmChanges", win.confirmModes[index].value)
                }
                ResetButton {
                    enabled: win.customConfirm
                    onClicked: win.app.changeSetting("confirmChanges", "always")
                }

                SettingLabel {
                    text: qsTr("Start in")
                    about: qsTr("The folder Koil lists when it's opened without one, written as in the path field (a pattern works too). Empty for your home folder. Used from the next start.")
                }
                // The dir (or pattern) Koil lists when it's opened with no path,
                // written as in the path field (from the home dir), or picked.
                // Empty for the home dir. Saved for the next start, not opened.
                Rectangle {
                    Layout.fillWidth: true
                    implicitWidth: 180 * win.zoom
                    implicitHeight: 26 * win.zoom
                    radius: 4 * win.zoom
                    color: win.theme.field
                    border.color: startInput.activeFocus ? win.accent : win.borderColor

                    TextInput {
                        id: startInput

                        x: 8 * win.zoom
                        width: parent.width - x - folderButton.width - 2 * win.zoom
                        height: parent.height
                        clip: true
                        text: win.settings.startDir
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: win.textColor
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        selectionColor: win.theme.highlight
                        selectedTextColor: win.theme.highlightedText
                        Accessible.name: qsTr("Start in")
                        onEditingFinished: {
                            win.settings.startDir = text.trim();
                            text = Qt.binding(() => win.settings.startDir);
                        }

                        // The home dir, as Koil shows it.
                        Text {
                            anchors.fill: parent
                            visible: !startInput.text
                            text: "~"
                            font: startInput.font
                            color: win.textColor
                            opacity: 0.5
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    SettingButton {
                        id: folderButton

                        anchors.right: parent.right
                        anchors.rightMargin: 2 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "M2 4.5 Q2 3.5 3 3.5 H6 L7.5 5 H13 Q14 5 14 6 V12 Q14 13 13 13 H3 Q2 13 2 12 Z"
                        tip: qsTr("Choose Folder")
                        onClicked: folderPicker.open()
                    }

                    FolderDialog {
                        id: folderPicker

                        onAccepted: win.settings.startDir = win.document.shownPath(win.document.urlToPath(selectedFolder))
                    }
                }
                ResetButton {
                    enabled: win.customStartDir
                    onClicked: win.settings.startDir = ""
                }

                SettingLabel {
                    text: qsTr("Shell")
                    about: qsTr("The shell `:!` runs commands in: a path, or a name on the `PATH`. Empty for the system's, which shows dimmed. The button lists those installed.")
                }
                // The shell :! runs commands in: a path, or a name on the PATH,
                // or one of those installed, which the button lists. Empty for
                // the system's, which shows dimmed.
                Rectangle {
                    id: shellPicker

                    // The shells installed: { name, path }.
                    property var shells: []

                    Layout.fillWidth: true
                    implicitWidth: 180 * win.zoom
                    implicitHeight: 26 * win.zoom
                    radius: 4 * win.zoom
                    color: win.theme.field
                    border.color: shellInput.activeFocus ? win.accent : win.borderColor

                    TextInput {
                        id: shellInput

                        x: 8 * win.zoom
                        width: parent.width - x - shellButton.width - 2 * win.zoom
                        height: parent.height
                        clip: true
                        text: win.settings.shell
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: win.textColor
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        selectionColor: win.theme.highlight
                        selectedTextColor: win.theme.highlightedText
                        Accessible.name: qsTr("Shell")
                        onEditingFinished: {
                            win.app.changeSetting("shell", text.trim());
                            text = Qt.binding(() => win.settings.shell);
                        }

                        Text {
                            anchors.fill: parent
                            visible: !shellInput.text
                            text: win.app.systemShell
                            font: shellInput.font
                            color: win.textColor
                            opacity: 0.5
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideMiddle
                        }
                    }
                    SettingButton {
                        id: shellButton

                        anchors.right: parent.right
                        anchors.rightMargin: 2 * win.zoom
                        anchors.verticalCenter: parent.verticalCenter
                        iconPath: "M5 6.5 L8 9.5 L11 6.5"
                        tip: qsTr("Show Shells")
                        onClicked: shellList.visible ? shellList.close() : shellList.open()
                    }

                    // Its own window, as the font list.
                    T.Popup {
                        id: shellList

                        y: shellPicker.height + 2 * win.zoom
                        width: shellPicker.width
                        height: Math.min(implicitContentHeight + topPadding + bottomPadding, 320 * win.zoom)
                        padding: 4 * win.zoom
                        popupType: Popup.Window
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                        onAboutToShow: shellPicker.shells = win.app.shellChoices()

                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.max(contentHeight, 24 * win.zoom)
                            model: shellPicker.shells
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollIndicator.vertical: ScrollIndicator {}

                            delegate: AbstractButton {
                                id: shellOption

                                required property var modelData

                                width: ListView.view.width
                                implicitHeight: 24 * win.zoom
                                focusPolicy: Qt.NoFocus
                                hoverEnabled: true
                                Accessible.name: modelData.name
                                onClicked: {
                                    win.app.changeSetting("shell", modelData.path);
                                    shellList.close();
                                }

                                background: Rectangle {
                                    radius: 3 * win.zoom
                                    color: shellOption.hovered ? win.accent : "transparent"
                                }
                                // Its name, then where it is, dimmed.
                                contentItem: Text {
                                    leftPadding: 4 * win.zoom
                                    rightPadding: 4 * win.zoom
                                    text: shellOption.modelData.name + "&nbsp;&nbsp;<font color=\"" + (shellOption.hovered
                                        ? win.theme.highlightedText : win.theme.dim) + "\">"
                                        + shellOption.modelData.path.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                        + "</font>"
                                    textFormat: Text.StyledText
                                    font.pixelSize: Math.round(13 * win.zoom)
                                    color: shellOption.hovered ? win.theme.highlightedText : win.textColor
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !shellPicker.shells.length
                                text: qsTr("No shells found")
                                font.pixelSize: Math.round(13 * win.zoom)
                                color: win.textColor
                                opacity: 0.6
                            }
                        }
                        background: Rectangle {
                            radius: 4 * win.zoom
                            color: win.theme.field
                            border.color: win.borderColor
                        }
                    }
                }
                ResetButton {
                    enabled: win.customShell
                    onClicked: win.app.changeSetting("shell", "")
                }

                SettingLabel {
                    text: qsTr("Shortcuts")
                    about: qsTr("Keys of yours, like `Space c` or `gc`, which run keys of yours as a macro does, in normal mode, visual mode or both. `Space q` lists them, and Koil's own.")
                }
                // The user's (see ShortcutsWindow), which Restore Defaults
                // leaves alone, and how many there are.
                Row {
                    spacing: 10 * win.zoom

                    TextButton {
                        theme: win.theme
                        text: qsTr("Edit Shortcuts…")
                        onClicked: win.app.openShortcuts()
                    }
                    SettingLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.app.shortcuts.length === 0 ? qsTr("None yet")
                            : win.app.shortcuts.length === 1 ? qsTr("1 shortcut")
                            : qsTr("%1 shortcuts").arg(win.app.shortcuts.length)
                    }
                }
                Item {}

                Item {}
                CodeLabel {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    theme: win.theme
                    markup: qsTr("`Space q` lists them.")
                    font.pixelSize: Math.round(12 * win.zoom)
                    color: win.textColor
                    opacity: 0.6
                }
                Item {}

                SettingLabel {
                    visible: win.app.isMac
                    text: qsTr("Open from Finder")
                    about: qsTr("Opens the folder selected in Finder here, even if Koil isn't open; it's also in a folder's right-click menu, under Services. In System Settings' Keyboard Shortcuts, it's under Services > Files and Folders.")
                }
                // "Open in Koil", the service on what's selected in Finder (a
                // folder, or a file's), whose shortcut macOS handles, launching
                // Koil if it isn't running. System Settings changes it, as it
                // can't be set from here. No link goes to Keyboard Shortcuts'
                // Services: Spotlight is the row under it (?Shortcuts lands on
                // Modifier Keys, the last row, and ?Services opens nothing).
                Row {
                    visible: win.app.isMac
                    spacing: 8 * win.zoom

                    Rectangle {
                        width: Math.max(70 * win.zoom, finderShortcutText.implicitWidth + 20 * win.zoom)
                        height: 26 * win.zoom
                        radius: 4 * win.zoom
                        color: win.theme.field
                        border.color: win.borderColor

                        Text {
                            id: finderShortcutText

                            anchors.centerIn: parent
                            text: win.finderShortcut || qsTr("None")
                            Accessible.role: Accessible.StaticText
                            Accessible.name: text
                            font.pixelSize: Math.round(13 * win.zoom)
                            color: win.textColor
                            opacity: win.finderShortcut ? 1 : 0.5
                        }
                    }
                    TextButton {
                        theme: win.theme
                        text: qsTr("Change in System Settings…")
                        onClicked: Qt.openUrlExternally("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Spotlight")
                    }
                }
                Item {
                    visible: win.app.isMac
                }

                Item {
                    visible: win.app.isMac
                }
                CodeLabel {
                    visible: win.app.isMac
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    theme: win.theme
                    markup: qsTr("Opens the folder selected in Finder in Koil.")
                    font.pixelSize: Math.round(12 * win.zoom)
                    color: win.textColor
                    opacity: 0.6
                }
                Item {
                    visible: win.app.isMac
                }

                SettingLabel {
                    visible: win.app.isMac
                    text: qsTr("Command line")
                    about: qsTr("Puts `koil` in `/usr/local/bin`, so that typed in a terminal, it opens Koil (`koil --help` says how). macOS asks for your password.")
                }
                // The `koil` command (see install.rs), a script in
                // /usr/local/bin that runs this Koil, which macOS asks an
                // admin's password to put there or take away.
                TextButton {
                    theme: win.theme
                    visible: win.app.isMac
                    enabled: !win.changingCommand
                    text: win.commandStatus === "installed" ? qsTr("Remove “koil” Command")
                        : win.commandStatus === "missing" ? qsTr("Install “koil” Command") : qsTr("Replace “koil” Command")
                    onClicked: {
                        win.changingCommand = true;
                        win.commandError = "";
                        win.document.changeCommand(win.commandStatus === "installed");
                    }
                }
                Item {
                    visible: win.app.isMac
                }

                Item {
                    visible: win.app.isMac
                }
                CodeLabel {
                    visible: win.app.isMac
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    theme: win.theme
                    markup: win.commandNote()
                    font.pixelSize: Math.round(12 * win.zoom)
                    color: win.commandError ? win.theme.error : win.textColor
                    opacity: win.commandError ? 1 : 0.6
                }
                Item {
                    visible: win.app.isMac
                }

                SettingLabel {
                    visible: win.app.isMac
                    text: qsTr("Shell environment")
                    about: qsTr("Shell commands (`:!`) get the `PATH` and other variables your shell has in a terminal, `.zshrc`'s too, read once as Koil opens: an app opened from Finder has only the system's `PATH`. Off, they get only the profile's (`.zprofile`), which may miss Homebrew.")
                }
                // Whether :! gets the environment read from the user's shell
                // (see shell.rs's `environment`), only on macOS, where an app
                // opened from Finder has only the system's PATH.
                Segmented {
                    visible: win.app.isMac
                    theme: win.theme
                    options: win.shellEnvironmentModes
                    current: win.shellEnvironmentModes.findIndex(m => m.value === win.settings.shellEnvironment)
                    onPicked: index => win.app.changeSetting("shellEnvironment", win.shellEnvironmentModes[index].value)
                }
                ResetButton {
                    visible: win.app.isMac
                    enabled: win.customShellEnvironment
                    onClicked: win.app.changeSetting("shellEnvironment", true)
                }

                Item {
                    visible: win.app.isMac
                }
                CodeLabel {
                    visible: win.app.isMac
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: -4 * win.zoom
                    theme: win.theme
                    markup: qsTr("Gives `:!` your shell's `PATH`, Homebrew's too.")
                    font.pixelSize: Math.round(12 * win.zoom)
                    color: win.textColor
                    opacity: 0.6
                }
                Item {
                    visible: win.app.isMac
                }
            }
        }

        TextButton {
            theme: win.theme
            Layout.alignment: Qt.AlignRight
            text: qsTr("Restore Defaults")
            enabled: win.customFontFamily || win.customFontSize || win.customLineNumbers || win.customSyntax
                || win.customWrap || win.customColorScheme || win.customDirsFirst || win.customConfirm
                || win.customStartDir || win.customShell || win.customShellEnvironment
            onClicked: win.restoreDefaults()
        }
    }
}
