import QtQuick
import QtQuick.Shapes

// Three nested arches seen head-on: a tunnel mouth. The innermost arch fills
// in once a session is connected, and `pulse` fades the outer rings while a
// connection is still being negotiated.
Item {
  id: root

  property real iconSize: 14
  property color color: "white"
  property bool filled: false
  property real pulse: 1.0

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real cx: width / 2
  readonly property real cy: height * 0.80
  readonly property real stroke: Math.max(1.2, iconSize * 0.11)
  readonly property real coreRadius: width * 0.13

  function shade(alpha) {
    return Qt.rgba(color.r, color.g, color.b, color.a * alpha)
  }

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4
    preferredRendererType: Shape.CurveRenderer

    Arch { radius: root.width * 0.44; alpha: 1.0 }
    Arch { radius: root.width * 0.29; alpha: 0.72 * root.pulse }

    ShapePath {
      strokeColor: root.filled ? "transparent" : root.shade(0.5 * root.pulse)
      fillColor: root.filled ? root.shade(1.0) : "transparent"
      strokeWidth: root.stroke
      capStyle: ShapePath.RoundCap
      startX: root.cx - root.coreRadius
      startY: root.cy

      PathAngleArc {
        centerX: root.cx
        centerY: root.cy
        radiusX: root.coreRadius
        radiusY: root.coreRadius
        startAngle: 180
        sweepAngle: 180
      }

      PathLine {
        x: root.cx - root.coreRadius
        y: root.cy
      }
    }
  }

  component Arch: ShapePath {
    id: arch
    property real radius: 0
    property real alpha: 1.0

    strokeColor: root.shade(arch.alpha)
    fillColor: "transparent"
    strokeWidth: root.stroke
    capStyle: ShapePath.RoundCap
    startX: root.cx - arch.radius
    startY: root.cy

    PathAngleArc {
      centerX: root.cx
      centerY: root.cy
      radiusX: arch.radius
      radiusY: arch.radius
      startAngle: 180
      sweepAngle: 180
    }
  }
}
