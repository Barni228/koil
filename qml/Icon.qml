import QtQuick
import QtQuick.Shapes

// An icon drawn with lines, from an SVG path in a 16×16 box. It's a vector
// shape scaled by the zoom, so it stays sharp.
Item {
    id: icon

    required property Theme theme
    property string path
    property color color: theme.text

    implicitWidth: 16 * theme.zoom
    implicitHeight: 16 * theme.zoom

    Shape {
        anchors.centerIn: parent
        width: 16
        height: 16
        scale: icon.theme.zoom
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: icon.color
            strokeWidth: 1.3
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg {
                path: icon.path
            }
        }
    }
}
