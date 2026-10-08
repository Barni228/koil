pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Templates as T

// The Settings window (Cmd+,): font, font size, line numbers, theme, when
// applying asks first, and the dir Koil starts in; and on macOS, the
// shortcut that opens Finder's folder, which System Settings changes, and
// the `koil` command, which it installs. It
// shows the saved settings, which Koil starts with; changes here are saved
// and apply at once (app.changeSetting), but the dir only at the next start.
// The zoom and :set change only the settings in use, so they don't show
// here. Each setting has a button that
// resets it to its default, and Restore Defaults resets them all.
Window {
    id: win

    // main.qml's window: the defaults, the fonts, changeSetting.
    required property var app
    // The saved settings: fontSize, fontFamily, number, relativeNumber,
    // colorScheme, confirmChanges, startDir.
    required property var settings
    required property Theme theme
    // main.qml's Document, for the folder picked (a var, so this file needs
    // no `import Koil`).
    required property var document

    readonly property real zoom: theme.zoom
    readonly property color textColor: theme.windowText
    readonly property color accent: theme.accent
    readonly property color borderColor: theme.dark ? Qt.tint(theme.window, "#30ffffff") : "#cecece"

    // Line numbers as one choice: :set nonu nornu, nu, rnu, or both.
    readonly property var lineNumberModes: [
        { label: qsTr("Off"), number: false, relative: false },
        { label: qsTr("On"), number: true, relative: false },
        { label: qsTr("Relative"), number: false, relative: true },
        { label: qsTr("Hybrid"), number: true, relative: true }
    ]
    readonly property int lineNumberMode: lineNumberModes.findIndex(
        m => m.number === settings.number && m.relative === settings.relativeNumber)
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
    readonly property bool customColorScheme: settings.colorScheme !== "system"
    readonly property bool customConfirm: settings.confirmChanges !== "always"
    readonly property bool customStartDir: settings.startDir !== ""

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
            return qsTr("Typed in a terminal, koil opens Koil (koil --help says how). It's in /usr/local/bin.");
        if (commandStatus === "otherKoil")
            return qsTr("/usr/local/bin/koil opens another copy of Koil, or one that was moved. Replacing it has koil open this one.");
        if (commandStatus === "other")
            return qsTr("/usr/local/bin/koil is another program. Replacing it has koil open Koil instead.");
        return qsTr("Puts koil in /usr/local/bin, so that typed in a terminal, it opens Koil (koil --help says how). macOS asks for your password.");
    }
    function restoreDefaults() {
        app.changeSetting("fontFamily", app.defaultFontFamily);
        setFontSize(app.defaultFontSize);
        setLineNumberMode(0);
        app.changeSetting("colorScheme", "system");
        app.changeSetting("confirmChanges", "always");
        settings.startDir = "";
    }

    // Shows the window, centered near the top of the main window the first
    // time and whenever it was closed. It opens with no field focused or
    // selected (a closed window keeps its focus item, which would get the
    // keys again, and the field its selection).
    function open() {
        if (!visible) {
            x = app.x + Math.round((app.width - width) / 2);
            y = app.y + Math.round(Math.min(80 * zoom, Math.max(0, (app.height - height) / 2)));
            fontSearch.focus = false;
            fontSearch.deselect();
            sizeInput.focus = false;
            sizeInput.deselect();
            startInput.focus = false;
            startInput.deselect();
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

    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: win.close()
    }
    // Not while the font list is open, which Esc closes.
    Shortcut {
        sequence: "Escape"
        enabled: !fontList.visible
        onActivated: win.close()
    }

    // A small button with an icon, which Tab reaches.
    component SettingButton: IconButton {
        theme: win.theme
        color: win.textColor
        focusPolicy: Qt.TabFocus
    }

    // Resets one setting; hidden while it has its default value.
    component ResetButton: SettingButton {
        iconPath: "M6 3 L3 6 L6 9 M3 6 H10 A3 3 0 0 1 10 12 H7"
        tip: qsTr("Reset to Default")
        opacity: enabled ? 1 : 0
    }

    // One of a few options, as a row of buttons.
    component Segmented: Rectangle {
        id: segmented

        property var options: [] // { label }
        property int current: -1

        signal picked(int index)

        implicitWidth: row.implicitWidth + 4 * win.zoom
        implicitHeight: 26 * win.zoom
        radius: 4 * win.zoom
        color: win.theme.field
        border.color: win.borderColor

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 2 * win.zoom

            Repeater {
                model: segmented.options

                AbstractButton {
                    id: option

                    required property var modelData
                    required property int index
                    readonly property bool selected: index === segmented.current

                    implicitWidth: optionText.implicitWidth + 20 * win.zoom
                    implicitHeight: segmented.height - 4 * win.zoom
                    focusPolicy: Qt.TabFocus
                    hoverEnabled: true
                    Accessible.name: modelData.label
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: selected
                    onClicked: segmented.picked(index)

                    background: Rectangle {
                        radius: 3 * win.zoom
                        color: option.selected ? win.accent : option.hovered ? win.theme.hover : "transparent"
                        border.color: option.visualFocus ? win.accent : "transparent"
                    }
                    contentItem: Text {
                        id: optionText

                        text: option.modelData.label
                        font.pixelSize: Math.round(13 * win.zoom)
                        color: option.selected ? win.theme.highlightedText : win.textColor
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // A button with a label.
    component TextButton: AbstractButton {
        id: textButton

        implicitWidth: implicitContentWidth + 24 * win.zoom
        implicitHeight: 26 * win.zoom
        opacity: enabled ? 1 : 0.4
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        Accessible.name: text

        background: Rectangle {
            radius: 4 * win.zoom
            color: textButton.hovered || textButton.pressed ? Qt.tint(win.theme.field, win.theme.hover) : win.theme.field
            border.color: textButton.visualFocus ? win.accent : win.borderColor
        }
        contentItem: Text {
            text: textButton.text
            font.pixelSize: Math.round(13 * win.zoom)
            color: win.textColor
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    component SettingLabel: Label {
        font.pixelSize: Math.round(13 * win.zoom)
        color: win.textColor
    }

    ColumnLayout {
        id: content

        x: 20 * win.zoom
        y: 16 * win.zoom
        spacing: 16 * win.zoom

        GridLayout {
            columns: 3
            columnSpacing: 12 * win.zoom
            rowSpacing: 10 * win.zoom

            SettingLabel {
                text: qsTr("Font")
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
            }
            Segmented {
                options: win.lineNumberModes
                current: win.lineNumberMode
                onPicked: index => win.setLineNumberMode(index)
            }
            ResetButton {
                enabled: win.customLineNumbers
                onClicked: win.setLineNumberMode(0)
            }

            SettingLabel {
                text: qsTr("Theme")
            }
            Segmented {
                options: win.colorSchemes
                current: win.colorSchemes.findIndex(t => t.value === win.settings.colorScheme)
                onPicked: index => win.app.changeSetting("colorScheme", win.colorSchemes[index].value)
            }
            ResetButton {
                enabled: win.customColorScheme
                onClicked: win.app.changeSetting("colorScheme", "system")
            }

            SettingLabel {
                text: qsTr("Ask before applying")
            }
            Segmented {
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
                visible: win.app.isMac
                text: qsTr("Open from Finder")
            }
            // "Open in Koil", the service in Finder's Services menu, whose
            // shortcut macOS handles, launching Koil if it isn't running.
            // System Settings changes it, as it can't be set from here; its
            // link opens Keyboard Shortcuts, but can't go on to Services.
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
                    text: qsTr("Change in System Settings…")
                    onClicked: Qt.openUrlExternally("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
                }
            }
            Item {
                visible: win.app.isMac
            }

            Item {
                visible: win.app.isMac
            }
            Text {
                visible: win.app.isMac
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.topMargin: -4 * win.zoom
                text: qsTr("Pressed in Finder, opens the folder it shows here, even if Koil isn't open. In Keyboard Shortcuts, it's under Services > General.")
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                font.pixelSize: Math.round(12 * win.zoom)
                color: win.textColor
                opacity: 0.6
                wrapMode: Text.WordWrap
            }
            Item {
                visible: win.app.isMac
            }

            SettingLabel {
                visible: win.app.isMac
                text: qsTr("Command line")
            }
            // The `koil` command (see install.rs), a script in
            // /usr/local/bin that runs this Koil, which macOS asks an
            // admin's password to put there or take away.
            TextButton {
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
            Text {
                visible: win.app.isMac
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.topMargin: -4 * win.zoom
                text: win.commandNote()
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                font.pixelSize: Math.round(12 * win.zoom)
                color: win.commandError ? win.theme.error : win.textColor
                opacity: win.commandError ? 1 : 0.6
                wrapMode: Text.WordWrap
            }
            Item {
                visible: win.app.isMac
            }
        }

        TextButton {
            Layout.alignment: Qt.AlignRight
            text: qsTr("Restore Defaults")
            enabled: win.customFontFamily || win.customFontSize || win.customLineNumbers || win.customColorScheme
                || win.customConfirm || win.customStartDir
            onClicked: win.restoreDefaults()
        }
    }
}
