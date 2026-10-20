import QtQuick
import QtQuick.Controls

// The text of a box (the hover box, a question, :help, the settings),
// which the wheel and the trackpad scroll, but not a drag, which selects
// text. A WheelHandler takes only a mouse wheel by default, and the
// trackpad's scrolls went to the popup, which dropped them.
Flickable {
    id: flickable

    // How far a notch of a mouse wheel scrolls.
    property real wheelStep: 60
    readonly property real maxY: Math.max(0, contentHeight - height)
    readonly property alias scrollBar: bar

    // The wheel or the trackpad scrolled it.
    signal scrolled

    function scrollTo(y) {
        contentY = Math.max(0, Math.min(maxY, y));
    }

    function scrollBy(dy) {
        scrollTo(contentY + dy);
    }

    interactive: false
    clip: true

    ScrollBar.vertical: ScrollBar {
        id: bar
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            flickable.scrollBy(-(event.pixelDelta.y || event.angleDelta.y / 120 * flickable.wheelStep));
            flickable.scrolled();
        }
    }
}
