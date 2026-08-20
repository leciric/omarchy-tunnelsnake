import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar entry point. The button lives here; everything else — state, polling,
// and the popup — belongs to Panel.qml, which is loaded lazily and handed the
// three things the bar host injects into this widget.
BarWidget {
  id: root
  moduleName: "linting.tunnelsnake"

  readonly property var panelItem: panelLoader.item
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  readonly property string tunnelState: panelItem ? panelItem.displayState : "disconnected"
  readonly property int sessionCount: panelItem ? panelItem.sessionCount : 0
  readonly property string tooltipLabel: panelItem ? panelItem.barTooltip : "Tunnelsnake"

  // An always-visible icon is the point of the widget for most people, but a
  // bar that is already crowded can keep it out of the way until a tunnel is up.
  readonly property bool hidden: setting("hideWhenIdle", false) === true
    && tunnelState !== "connected" && tunnelState !== "connecting"

  readonly property bool needsAttention: tunnelState === "needs-auth" || tunnelState === "failed"

  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color barUrgent: bar ? bar.urgent : Color.urgent
  readonly property color iconColor: tunnelState === "connected"
    ? barForeground
    : (needsAttention ? barUrgent : Qt.darker(barForeground, 1.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }
  function refresh() { if (panelItem) panelItem.refresh() }

  visible: !hidden
  implicitWidth: hidden ? 0 : button.implicitWidth
  implicitHeight: hidden ? 0 : button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipLabel
    dimmed: root.tunnelState !== "connected"

    iconComponent: Component {
      Item {
        TunnelIcon {
          id: barIcon
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: root.iconColor
          filled: root.tunnelState === "connected"

          SequentialAnimation on pulse {
            running: root.tunnelState === "connecting"
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
          }
        }

        // A tunnel waiting on sign-in, or a dead one, is worth a mark; so is
        // more than one session at once.
        Text {
          visible: root.needsAttention || root.sessionCount > 1
          anchors.right: barIcon.right
          anchors.top: barIcon.top
          anchors.rightMargin: -Style.space(2)
          anchors.topMargin: -Style.space(2)
          text: root.needsAttention ? "!" : String(root.sessionCount)
          color: root.needsAttention ? root.barUrgent : Color.accent
          font.family: button.fontFamily
          font.pixelSize: Math.max(7, Math.round(button.fontSize * 0.5))
          font.bold: true
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.refresh()
      else if (mouseButton === Qt.MiddleButton) { if (root.panelItem) root.panelItem.toggleTunnel() }
      else root.toggle()
    }
  }
}
