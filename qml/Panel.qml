pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// A box over the editor, as in VS Code: a shade off the background, with a
// border and a shadow. The hover box, tooltips, :help and :confirm use one.
Rectangle {
    id: panel

    required property Theme theme
    // A dialog's (:help, :confirm): rounder, with a deeper shadow.
    property bool raised: false

    radius: (raised ? 6 : 4) * theme.zoom
    color: theme.panel
    border.color: theme.panelBorder
    layer.enabled: visible
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: panel.raised ? 0.8 : 0.6
        shadowVerticalOffset: panel.raised ? 4 : 2
        shadowColor: panel.theme.dark ? "#a0000000" : panel.raised ? "#50000000" : "#40000000"
    }
}
