import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The popup behind the bar icon: tunnel state and a switch up top, every
// running openvpn3 session in the middle, every profile you can dial at the
// bottom. BarWidget.qml owns the button and injects `bar`, `settings`, and
// `anchorItem` into this item.
Panel {
  id: root
  moduleName: "linting.tunnelsnake"
  ipcTarget: "linting.tunnelsnake"

  property Item anchorItem: null
  property var hostWidget: null

  // bin/tunnelsnake sits next to this file; strip the URL scheme so Process
  // gets a plain path.
  readonly property string pluginDir: {
    var dir = String(Qt.resolvedUrl("."))
    if (dir.indexOf("file://") === 0) dir = dir.substring(7)
    return dir.replace(/\/$/, "")
  }

  // Read by the bar widget for the icon and its tooltip.
  readonly property string displayState: vpn.displayState
  readonly property bool tunnelUp: vpn.displayState === "connected"
  readonly property bool tunnelBusy: vpn.displayState === "connecting"
  readonly property int sessionCount: vpn.sessions.length
  readonly property string barTooltip: {
    if (!vpn.installed) return "Tunnelsnake · openvpn3 not installed"
    var label = Model.stateLabel(vpn.displayState, vpn.device)
    if (vpn.sessions.length > 1) label += " · " + vpn.sessions.length + " sessions"
    return "Tunnelsnake · " + label
  }

  property string focusSection: "header"
  property int sessionIndex: 0
  property int profileIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  readonly property var activePhrases: [
    "Slithering through",
    "Tunnel snakes rule",
    "Wrapping packets",
    "Holding the burrow",
    "Digging deeper",
    "Coiled and quiet",
    "Shedding plaintext",
    "Watching the wire"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: vpn.displayState === "connected" ? foreground : dim
  readonly property string toggleHint: vpn.active ? "Disconnect the tunnel" : "Connect the tunnel"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed
  readonly property bool showSessions: vpn.sessions.length > 0
  readonly property bool showProfiles: vpn.profiles.length > 0

  function refresh() {
    vpn.refresh()
    vpn.refreshProfiles()
  }

  // Middle-clicking the bar icon connects or disconnects without opening the
  // popup at all.
  function toggleTunnel() {
    vpn.toggleTunnel()
  }

  function selectedSession() {
    if (vpn.sessions.length === 0) return null
    return vpn.sessions[Math.max(0, Math.min(sessionIndex, vpn.sessions.length - 1))]
  }

  function selectedProfile() {
    if (vpn.profiles.length === 0) return null
    return vpn.profiles[Math.max(0, Math.min(profileIndex, vpn.profiles.length - 1))]
  }

  function ensureCursor() {
    if (sessionIndex >= vpn.sessions.length) sessionIndex = Math.max(0, vpn.sessions.length - 1)
    if (profileIndex >= vpn.profiles.length) profileIndex = Math.max(0, vpn.profiles.length - 1)
    if (sessionIndex < 0) sessionIndex = 0
    if (profileIndex < 0) profileIndex = 0
    if (focusSection === "sessions" && !showSessions) focusSection = showProfiles ? "profiles" : "header"
    if (focusSection === "profiles" && !showProfiles) focusSection = showSessions ? "sessions" : "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return

    if (focusSection === "header") {
      if (dy > 0) {
        if (showSessions) { focusSection = "sessions"; sessionIndex = 0 }
        else if (showProfiles) { focusSection = "profiles"; profileIndex = 0 }
        scrollCursorIntoView()
      }
      return
    }

    if (focusSection === "sessions") {
      if (dy < 0 && sessionIndex === 0) { setHeaderCursor(); return }
      if (dy > 0 && sessionIndex === vpn.sessions.length - 1) {
        if (showProfiles) { focusSection = "profiles"; profileIndex = 0; scrollCursorIntoView() }
        return
      }
      sessionIndex = Math.max(0, Math.min(vpn.sessions.length - 1, sessionIndex + dy))
      scrollCursorIntoView()
      return
    }

    if (focusSection === "profiles") {
      if (dy < 0 && profileIndex === 0) {
        if (showSessions) { focusSection = "sessions"; sessionIndex = vpn.sessions.length - 1; scrollCursorIntoView() }
        else setHeaderCursor()
        return
      }
      profileIndex = Math.max(0, Math.min(vpn.profiles.length - 1, profileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") vpn.toggleTunnel()
    else if (focusSection === "sessions") {
      var session = selectedSession()
      if (session) vpn.disconnectSession(session.path)
    } else if (focusSection === "profiles") {
      var profile = selectedProfile()
      if (profile) vpn.connectProfile(profile.path)
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function setSessionCursor(index) {
    cursorActive = true
    focusSection = "sessions"
    sessionIndex = index
  }

  function setProfileCursor(index) {
    cursorActive = true
    focusSection = "profiles"
    profileIndex = index
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "sessions" && sessionColumn && sessionIndex < sessionColumn.children.length) {
      scrollItemIntoView(sessionColumn.children[sessionIndex])
    } else if (focusSection === "profiles" && profileColumn && profileIndex < profileColumn.children.length) {
      scrollItemIntoView(profileColumn.children[profileIndex])
    }
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
    pluginDir: root.pluginDir
  }

  Connections {
    target: vpn
    function onSessionsChanged() { root.ensureCursor() }
    function onProfilesChanged() { root.ensureCursor() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "c" || t === "C") vpn.connectProfile("")
        else if (t === "d" || t === "D") vpn.disconnectAll()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, so panel
            // state is reached through this wrapper instead.
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Tunnelsnake"
              meta: vpn.displayState === "connected" ? root.heroPhraseText : Model.stateLabel(vpn.displayState, vpn.device)
              detail: vpn.displayState === "connected" && vpn.device !== "" ? vpn.device : ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: vpn.displayState === "connected" ? 1.0 : 0.55

              iconComponent: Component {
                TunnelIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  filled: vpn.displayState === "connected"

                  SequentialAnimation on pulse {
                    running: vpn.displayState === "connecting"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
                  }
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: vpn.installed
                  checked: vpn.active
                  busy: vpn.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: vpn.toggleTunnel()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: text !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: vpn.displayState === "connected"
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Interface"; value: vpn.device !== "" ? vpn.device : "—" }
            InfoPair { label: "Address"; value: vpn.ipv4 !== "" ? vpn.ipv4 : "—" }
            InfoPair { visible: vpn.dnsServers.length > 0; label: "DNS"; value: vpn.dnsServers.join(", ") }
            InfoPair { visible: vpn.dnsDomains.length > 0; label: "Domains"; value: vpn.dnsDomains.join(" ") }
            InfoPair {
              visible: vpn.bytesIn > 0 || vpn.bytesOut > 0
              label: "Transfer"
              value: "↓ " + Model.formatBytes(vpn.bytesIn) + "   ↑ " + Model.formatBytes(vpn.bytesOut)
            }
          }

          PanelSeparator {
            visible: vpn.installed
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SESSIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: !root.showSessions
              width: parent.width
              text: "No tunnels running."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: sessionColumn
              visible: root.showSessions
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.sessions
                SessionRow {
                  required property var modelData
                  required property int index
                  width: sessionColumn.width
                  session: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator {
            visible: root.showProfiles
            foreground: root.foreground
          }

          Column {
            visible: root.showProfiles
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PROFILES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: profileColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.profiles
                ProfileRow {
                  required property var modelData
                  required property int index
                  width: profileColumn.width
                  profile: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: !vpn.installed
            width: parent.width
            text: "openvpn3 is not installed. Install it with: omarchy pkg add openvpn3"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && vpn.displayState === "connected"
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component SessionRow: CursorSurface {
    id: sessionRow
    property var session: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "sessions" && root.sessionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: sessionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSessionCursor(sessionRow.rowIndex)
      onClicked: if (sessionRow.session) vpn.disconnectSession(sessionRow.session.path)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        implicitWidth: Style.space(7)
        implicitHeight: Style.space(7)
        radius: implicitWidth / 2
        color: sessionRow.session && sessionRow.session.state === "connected"
          ? root.foreground
          : (sessionRow.session && sessionRow.session.state === "connecting" ? Color.accent : root.dim)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: sessionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: Model.sessionTitle(sessionRow.session)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.sessionMeta(sessionRow.session, vpn.nowMs)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: "󰅖"
        tooltipText: "Disconnect"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !vpn.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (sessionRow.session) vpn.disconnectSession(sessionRow.session.path)
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property bool isActive: Model.isProfileActive(profileRow.profile, vpn.sessions)
    readonly property bool isDefault: vpn.defaultProfile() === (profileRow.profile ? profileRow.profile.path : "")

    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    current: isActive
    foreground: root.foreground
    implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: root.setProfileCursor(profileRow.rowIndex)
      onClicked: {
        if (!profileRow.profile) return
        if (profileRow.isActive) vpn.disconnectAll()
        else vpn.connectProfile(profileRow.profile.path)
      }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: profileRow.isActive ? "󰅠" : "󰦝"
        color: profileRow.isActive ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: profileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: Model.profileLabel(profileRow.profile) + (profileRow.isDefault ? "  ·  default" : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: Model.profileMeta(profileRow.profile, vpn.home)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      id: infoLabel
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: Math.max(0, parent.width - infoLabel.implicitWidth - infoValue.implicitWidth - parent.spacing * 2)
      height: 1
    }

    Text {
      id: infoValue
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
