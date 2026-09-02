import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
  property int pickerIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0

  // The file picker takes over the whole panel while it is open: browsing for
  // a profile has nothing to say about the tunnel you are already running, and
  // a folder deep in $HOME needs every row it can get.
  property bool picking: false

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
  readonly property string toggleHint: vpn.needsAuth
    ? "Open the sign-in page"
    : (vpn.active ? "Disconnect the tunnel" : "Connect the tunnel")
  readonly property bool headerHasCursor: cursorActive && focusSection === "header" && vpn.installed
  readonly property bool showSessions: vpn.sessions.length > 0
  // Always on when openvpn3 is: the last row is the way into the file picker,
  // and a fresh install with no profiles found is exactly when it is needed.
  readonly property bool showProfiles: vpn.installed
  readonly property bool showAuth: vpn.displayState === "needs-auth" || vpn.displayState === "failed"

  // The profiles you can dial, plus the row that opens the picker. Keeping the
  // picker in the same list is what makes it reachable with the keyboard
  // without teaching the cursor about a section with one row in it.
  readonly property var profileRows: vpn.profiles.concat([{
    kind: "browse",
    name: "Choose a profile file…",
    path: ""
  }])

  // What the picker draws: the way back out of the folder, then its contents.
  readonly property var pickerRows: {
    var rows = []
    if (vpn.browseParent !== "") rows.push({ kind: "up", name: "..", path: vpn.browseParent })
    var entries = vpn.browseEntries
    for (var i = 0; i < entries.length; i++) rows.push(entries[i])
    return rows
  }

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
    if (profileRows.length === 0) return null
    return profileRows[Math.max(0, Math.min(profileIndex, profileRows.length - 1))]
  }

  function selectedPickerRow() {
    if (pickerRows.length === 0) return null
    return pickerRows[Math.max(0, Math.min(pickerIndex, pickerRows.length - 1))]
  }

  function openPicker() {
    picking = true
    cursorActive = true
    focusSection = "picker"
    pickerIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    vpn.browse(vpn.browseStart())
  }

  function closePicker() {
    picking = false
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function enterFolder(path) {
    if (!path) return
    vpn.browse(path)
    pickerIndex = 0
    if (panelFlick) panelFlick.contentY = 0
  }

  function activatePickerRow(entry) {
    if (!entry) return
    if (entry.kind === "up" || entry.kind === "dir") { enterFolder(entry.path); return }
    vpn.chooseProfile(entry.path)
    closePicker()
  }

  // The sections actually on screen, top to bottom. Everything about cursor
  // movement is derived from this, so a section appearing or vanishing needs
  // no other change.
  function sectionOrder() {
    if (picking) return ["picker"]
    var order = ["header"]
    if (showAuth) order.push("auth")
    if (showSessions) order.push("sessions")
    if (showProfiles) order.push("profiles")
    return order
  }

  function sectionLength(section) {
    if (section === "sessions") return vpn.sessions.length
    if (section === "profiles") return profileRows.length
    if (section === "picker") return pickerRows.length
    return 1
  }

  function sectionCursor(section) {
    if (section === "sessions") return sessionIndex
    if (section === "profiles") return profileIndex
    if (section === "picker") return pickerIndex
    return 0
  }

  function setSectionCursor(section, value) {
    if (section === "sessions") sessionIndex = value
    else if (section === "profiles") profileIndex = value
    else if (section === "picker") pickerIndex = value
  }

  function ensureCursor() {
    if (sessionIndex >= vpn.sessions.length) sessionIndex = Math.max(0, vpn.sessions.length - 1)
    if (profileIndex >= profileRows.length) profileIndex = Math.max(0, profileRows.length - 1)
    if (pickerIndex >= pickerRows.length) pickerIndex = Math.max(0, pickerRows.length - 1)
    if (sessionIndex < 0) sessionIndex = 0
    if (profileIndex < 0) profileIndex = 0
    if (pickerIndex < 0) pickerIndex = 0
    if (sectionOrder().indexOf(focusSection) === -1) focusSection = picking ? "picker" : "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()

    // Left and right walk the folder tree, the way they do in every other file
    // list: out to the parent, in to the folder under the cursor.
    if (picking && dx !== 0) {
      if (dx < 0) enterFolder(vpn.browseParent)
      else {
        var row = selectedPickerRow()
        if (row && (row.kind === "dir" || row.kind === "up")) enterFolder(row.path)
      }
      return
    }
    if (dy === 0) return

    var order = sectionOrder()
    var at = order.indexOf(focusSection)
    if (at === -1) { focusSection = order[0]; return }

    var next = sectionCursor(focusSection) + dy
    if (next >= 0 && next < sectionLength(focusSection)) {
      setSectionCursor(focusSection, next)
      scrollCursorIntoView()
      return
    }

    var section = at + (dy > 0 ? 1 : -1)
    if (section < 0 || section >= order.length) return
    focusSection = order[section]
    setSectionCursor(focusSection, dy > 0 ? 0 : Math.max(0, sectionLength(focusSection) - 1))
    if (focusSection === "header" && panelFlick) panelFlick.contentY = 0
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") vpn.toggleTunnel()
    else if (focusSection === "auth") {
      if (vpn.needsAuth) vpn.openAuthUrl()
      else vpn.reconnect()
    } else if (focusSection === "sessions") {
      var session = selectedSession()
      if (session) vpn.disconnectSession(session.path)
    } else if (focusSection === "profiles") {
      var profile = selectedProfile()
      if (!profile) return
      if (profile.kind === "browse") openPicker()
      else if (Model.isProfileActive(profile, vpn.sessions)) vpn.disconnectAll()
      else vpn.connectProfile(profile.path)
    } else if (focusSection === "picker") {
      activatePickerRow(selectedPickerRow())
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

  function setPickerCursor(index) {
    cursorActive = true
    focusSection = "picker"
    pickerIndex = index
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
    } else if (focusSection === "picker" && pickerColumn && pickerIndex < pickerColumn.children.length) {
      scrollItemIntoView(pickerColumn.children[pickerIndex])
    }
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    picking = false
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

  // Scriptable from hooks and keybindings: `omarchy-shell linting.tunnelsnake
  // signin`, `... connect`, `... status`, and so on.
  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function connect(): string { vpn.connectProfile(""); return "ok" }
    function disconnect(): string { vpn.disconnectAll(); return "ok" }
    function reconnect(): string { vpn.reconnect(); return "ok" }
    function signin(): string { vpn.openAuthUrl(); return vpn.authUrl !== "" ? vpn.authUrl : "no sign-in pending" }
    function status(): string { return vpn.displayState }
    function pick(): string { root.open(); root.openPicker(); return "ok" }
    function profile(): string { return vpn.defaultProfile() }
  }

  Connections {
    target: vpn
    function onSessionsChanged() { root.ensureCursor() }
    function onProfilesChanged() { root.ensureCursor() }
    function onBrowseEntriesChanged() { root.ensureCursor() }
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
      // Esc backs out of the picker before it closes the panel, so a wrong
      // turn in a folder tree does not cost you the whole popup.
      onCloseRequested: root.picking ? root.closePicker() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (root.picking) {
          // Nothing here should touch the tunnel; you are picking a file.
          if (key === ".") vpn.toggleHidden()
          else if (key === "u") root.enterFolder(vpn.browseParent)
          return
        }
        if (key === "r") root.refresh()
        else if (key === "c") vpn.connectProfile("")
        else if (key === "d") vpn.disconnectAll()
        else if (key === "f") root.openPicker()
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

          Column {
            id: mainColumn
            visible: !root.picking
            width: parent.width
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

            AuthRow {
              visible: root.showAuth
              width: parent.width
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
                  model: root.profileRows
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

          // The picker. One folder at a time, walked with the same keys as the
          // rest of the panel: up and down to move, left and right to leave and
          // enter a folder, Enter to take what is under the cursor.
          Column {
            id: pickerView
            visible: root.picking
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                PanelSectionHeader {
                  text: "CHOOSE A PROFILE"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Text {
                  Layout.fillWidth: true
                  text: Model.homeRelative(vpn.browseDir, vpn.home)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  // The tail of a path says which folder you are in; the head
                  // only says how deep it is.
                  elide: Text.ElideLeft
                }
              }

              PanelActionButton {
                iconText: vpn.browseHidden ? "󰈈" : "󰈉"
                tooltipText: vpn.browseHidden ? "Hide dot-folders (.)" : "Show dot-folders (.)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignVCenter
                onClicked: vpn.toggleHidden()
              }

              PanelActionButton {
                iconText: "󰅖"
                tooltipText: "Back to the panel (Esc)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.closePicker()
              }
            }

            Text {
              visible: text !== ""
              width: parent.width
              text: vpn.browseError !== "" ? vpn.browseError
                : (vpn.browseTruncated ? "Too many entries to list — open a narrower folder." : "")
              color: vpn.browseError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Column {
              id: pickerColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.pickerRows
                PickerRow {
                  required property var modelData
                  required property int index
                  width: pickerColumn.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }

            Text {
              visible: root.pickerRows.length === 0 && vpn.browseError === ""
              width: parent.width
              text: "No folders and no profiles here."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSeparator {
              foreground: root.foreground
            }

            // Picking one file sets the default profile; pointing the widget at
            // the folder lists every profile in it instead, which is what you
            // want when there is more than one tunnel to switch between.
            Button {
              width: parent.width
              text: "Scan this folder for profiles"
              iconText: "󰉋"
              bordered: true
              leftAlign: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: vpn.browseDir !== ""
              onClicked: {
                vpn.chooseProfilesDir(vpn.browseDir)
                root.closePicker()
              }
            }
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

  // openvpn3 parks SSO profiles until the sign-in URL is visited, and drops
  // them on a failed handshake. Both states need one click to move forward.
  component AuthRow: CursorSurface {
    id: authRow
    readonly property bool signIn: vpn.needsAuth

    hasCursor: root.cursorActive && root.focusSection === "auth"
    foreground: root.foreground
    implicitHeight: authContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "auth"
      }
      onClicked: authRow.signIn ? vpn.openAuthUrl() : vpn.reconnect()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: authRow.signIn ? "󰌾" : "󰜺"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: authContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: authRow.signIn ? "Sign in to finish connecting" : "Connection failed — try again"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: authRow.signIn
            ? (vpn.authUrl !== "" ? "Open the sign-in page in your browser" : "Reconnect to get a new sign-in link")
            : "Drop the dead session and reconnect"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: authRow.signIn ? "󰖟" : "󰑐"
        tooltipText: authRow.signIn ? "Open sign-in page" : "Reconnect"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !vpn.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: authRow.signIn ? vpn.openAuthUrl() : vpn.reconnect()
      }
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
    // The last row in the list is not a profile at all: it is the way into the
    // file picker, for the profile that is not in any folder we scan.
    readonly property bool isBrowse: profileRow.profile && profileRow.profile.kind === "browse"
    readonly property bool isActive: !isBrowse && Model.isProfileActive(profileRow.profile, vpn.sessions)
    readonly property bool isDefault: !isBrowse && profileRow.profile
      && vpn.activeProfile === profileRow.profile.path

    hasCursor: root.cursorActive && root.focusSection === "profiles" && root.profileIndex === rowIndex
    current: isActive
    foreground: root.foreground
    implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpn.busy && !profileRow.isBrowse ? Qt.ArrowCursor : Qt.PointingHandCursor
      onEntered: root.setProfileCursor(profileRow.rowIndex)
      onClicked: {
        if (!profileRow.profile) return
        if (profileRow.isBrowse) root.openPicker()
        else if (profileRow.isActive) vpn.disconnectAll()
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
        text: profileRow.isBrowse ? "󰉋" : (profileRow.isActive ? "󰅠" : "󰦝")
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
          text: profileRow.isBrowse
            ? String(profileRow.profile.name)
            : Model.profileLabel(profileRow.profile) + (profileRow.isDefault ? "  ·  default" : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: profileRow.isBrowse
            ? "Anywhere on disk, or a whole folder to scan"
            : Model.profileMeta(profileRow.profile, vpn.home)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // Connecting to a profile is a click; making it the one the switch and
      // the bar icon dial needs its own.
      PanelActionButton {
        visible: !profileRow.isBrowse && !profileRow.isDefault
        iconText: "󰐃"
        tooltipText: "Make this the default profile"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (profileRow.profile) vpn.chooseProfile(profileRow.profile.path)
      }
    }
  }

  // One row of the file picker: the way up, a folder to walk into, or a profile
  // to take.
  component PickerRow: CursorSurface {
    id: pickerRow
    property var entry: null
    property int rowIndex: 0
    readonly property bool isUp: pickerRow.entry && pickerRow.entry.kind === "up"
    readonly property bool isDir: pickerRow.entry
      && (pickerRow.entry.kind === "dir" || pickerRow.entry.kind === "up")
    readonly property bool isCurrent: !isDir && pickerRow.entry
      && String(pickerRow.entry.path) === vpn.configuredProfile

    hasCursor: root.cursorActive && root.focusSection === "picker" && root.pickerIndex === rowIndex
    current: isCurrent
    foreground: root.foreground
    implicitHeight: pickerContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setPickerCursor(pickerRow.rowIndex)
      onClicked: root.activatePickerRow(pickerRow.entry)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: pickerRow.isUp ? "󰁝" : (pickerRow.isDir ? "󰉋" : "󰖂")
        color: pickerRow.isDir ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: pickerContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: pickerRow.isUp
            ? Model.homeRelative(String(pickerRow.entry.path), vpn.home)
            : String(pickerRow.entry ? pickerRow.entry.name : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: pickerRow.isUp ? Text.ElideLeft : Text.ElideRight
        }

        Text {
          visible: text !== ""
          Layout.fillWidth: true
          text: pickerRow.isUp ? "Up one folder"
            : (pickerRow.isCurrent ? "the default profile right now" : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      // A profile openvpn3 holds itself keeps working when the file moves, and
      // shows up for every other openvpn3 tool on the machine.
      PanelActionButton {
        visible: !pickerRow.isDir
        iconText: "󰋺"
        tooltipText: "Import into openvpn3"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !vpn.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: if (pickerRow.entry) vpn.importProfile(pickerRow.entry.path)
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
