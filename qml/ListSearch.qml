pragma ComponentBehavior: Bound

import QtQuick

// The line a PickList's search is typed on, as the help's, at the bottom
// of what draws the list (which gives it the list's width, and `inset`,
// how far in its text is): the search being typed, else the one the list
// shows the lines of, how many lines those are, and how many picked ones
// aren't among them. It shows only while there's a search. It has the keys
// while the search is typed (/ starts it: PickList.startFilter), and gives
// them back to `owner`, which has the list's, once it's done: Enter keeps
// the search, Esc puts back the one before, Backspace with nothing typed
// ends it, and Up and Down move the list's cursor meanwhile (PageDown
// and PageUp a page).
Item {
    id: line

    required property Theme theme
    required property PickList picks
    // What has the list's keys.
    required property Item owner
    property font font: theme.font
    property color color: theme.text
    property real inset: 0
    readonly property real zoom: theme.zoom

    height: visible ? Math.ceil(metrics.height) + 8 * zoom : 0
    visible: picks.filtering || picks.filter !== ""

    FontMetrics {
        id: metrics

        font: line.font
    }

    // Typing starts from the search there is, selected, so it's replaced.
    // The keys go back by `focus`, not forced: a question closed while
    // its search was typed mustn't take them from the editor.
    Connections {
        target: line.picks

        function onFilteringChanged() {
            if (line.picks.filtering) {
                field.text = line.picks.filter;
                field.selectAll();
                field.forceActiveFocus();
            } else {
                line.owner.focus = true;
            }
        }
    }

    Rectangle {
        x: 1
        width: line.width - 2
        height: 1
        color: line.theme.panelBorder
    }
    Text {
        id: prefix

        anchors.left: parent.left
        anchors.leftMargin: line.inset
        anchors.verticalCenter: parent.verticalCenter
        width: line.picks.filtering ? implicitWidth : Math.min(implicitWidth, note.x - x - 12 * line.zoom)
        text: "/" + (line.picks.filtering ? "" : line.picks.filter)
        font: line.font
        color: line.color
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    TextInput {
        id: field

        anchors.left: prefix.right
        anchors.right: note.left
        anchors.rightMargin: 12 * line.zoom
        anchors.baseline: prefix.baseline
        visible: line.picks.filtering
        clip: true
        font: line.font
        color: line.color
        selectByMouse: true
        selectionColor: line.theme.highlight
        selectedTextColor: line.theme.highlightedText
        onTextChanged: {
            if (line.picks.filtering)
                line.picks.setFilter(text);
        }
        // Something else took the keys (a click on a button that keeps
        // them): the search stays as typed.
        onFocusChanged: {
            if (!focus)
                line.picks.finishFilter(true);
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                line.picks.finishFilter(true);
            else if (event.key === Qt.Key_Escape)
                line.picks.finishFilter(false);
            else if (event.key === Qt.Key_Backspace && text === "")
                line.picks.finishFilter(true);
            else if (event.key === Qt.Key_Down)
                line.picks.moveRow(1);
            else if (event.key === Qt.Key_Up)
                line.picks.moveRow(-1);
            else if (event.key === Qt.Key_PageDown)
                line.picks.movePage(1);
            else if (event.key === Qt.Key_PageUp)
                line.picks.movePage(-1);
            else if (event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab)
                return;
            event.accepted = true;
        }
    }
    Text {
        id: note

        anchors.right: parent.right
        anchors.rightMargin: line.inset
        anchors.baseline: prefix.baseline
        text: qsTr("%1 of %2").arg(line.picks.shownCount).arg(line.picks.items.length)
            + (line.picks.hiddenPicked ? qsTr(" · %1 picked not shown").arg(line.picks.hiddenPicked) : "")
        font: line.font
        color: line.picks.shownCount ? line.theme.dim : line.theme.error
        textFormat: Text.PlainText
    }
}
