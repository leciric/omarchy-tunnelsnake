import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// All openvpn3 and Firezone traffic goes through bin/tunnelsnake, which
// answers in JSON.
// This item owns the polling, the optimistic state, and the one-shot actions;
// Panel.qml only reads properties and calls the functions below.
Item {
  id: root

  property var settings: ({})
  property string pluginDir: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string helperPath: pluginDir === "" ? "" : pluginDir + "/bin/tunnelsnake"

  property bool installed: true
  // disconnected | connecting | needs-auth | connected | failed | paused |
  // missing | unknown
  property string tunnelState: "disconnected"
  property string activePath: ""
  property var sessions: []
  property var profiles: []
  property string device: ""
  property string ipv4: ""
  property var dnsServers: []
  property var dnsDomains: []
  property real bytesIn: 0
  property real bytesOut: 0
  // Live sign-in URL, re-read from openvpn3 on every poll for as long as the
  // session sits waiting, so it survives a shell restart and can be reopened
  // as many times as the browser tab gets lost.
  property string authUrl: ""
  // Set while a connect we started is still expected to produce a URL, so the
  // browser opens by itself once — and only once, not on every poll.
  property bool _autoOpenAuth: false
  // Firezone's half: one tunnel, owned by the Firezone app. See Model.parseFirezone.
  property var firezone: Model.parseFirezone(null)
  // Same optimistic trick as _desired, for the Firezone tunnel alone.
  property int _fzDesired: -1
  // Set when a connect found no stored sign-in and opened the Firezone window
  // instead; `firezone status` cannot tell "signed out" from "disconnected".
  property bool fzSignInPending: false
  // Firezone's own last failure, drawn in its section. Kept apart from
  // lastError, which every poll rewrites.
  property string fzError: ""
  property string actionStatus: ""
  property string lastError: ""
  property bool refreshing: false
  property double nowMs: Date.now()

  // The file picker's view of one directory. The helper walks the disk, this
  // holds the answer, and Panel.qml draws it.
  property string browseDir: ""
  property string browseParent: ""
  property var browseEntries: []
  property bool browseTruncated: false
  property bool browseHidden: false
  property string browseError: ""
  property bool browsing: false
  // Navigating is faster than a Process round trip, so remember where the last
  // click wanted to go instead of dropping it.
  property string _queuedBrowse: ""
  property bool _hasQueuedBrowse: false
  // What to say once a settings write lands. Held here because the answer
  // arrives on a process exit, long after the click that caused it.
  property string _saveMessage: ""
  property bool _reloadProfilesAfterAction: false

  // Connecting and disconnecting both take several seconds, so the switch
  // follows this optimistic value until reality catches up: -1 means "just
  // report what openvpn3 says", 0/1 means a request is still in flight.
  property int _desired: -1

  readonly property bool connected: tunnelState === "connected"
  readonly property bool busy: actionProcess.running || _desired !== -1
  readonly property bool active: _desired === -1 ? (tunnelState === "connected" || tunnelState === "connecting") : (_desired === 1)

  // What the icon and the hero draw: a pending request outranks the last poll.
  readonly property string displayState: {
    if (!installed) return "missing"
    // A session parked on sign-in or dead on a failed handshake is a real
    // answer; never paint it as still-connecting just because a request is in
    // flight.
    if (tunnelState === "needs-auth" || tunnelState === "failed") return tunnelState
    if (_desired === 1 && tunnelState !== "connected") return "connecting"
    if (_desired === 0 && tunnelState !== "disconnected") return "connecting"
    return tunnelState
  }

  readonly property bool needsAuth: displayState === "needs-auth"

  readonly property bool fzInstalled: firezone.installed
  readonly property bool fzBusy: firezoneProcess.running || _fzDesired !== -1
  readonly property string fzDisplayState: {
    var state = firezone.state
    if (_fzDesired === 1 && state !== "connected" && !fzSignInPending) return "connecting"
    if (_fzDesired === 0 && state === "connected") return "connecting"
    if (fzSignInPending && state !== "connected") return "signed-out"
    return state
  }
  readonly property bool fzActive: fzDisplayState === "connected" || fzDisplayState === "connecting"

  // What the bar icon and the hero draw, across both clients. A session that
  // needs you (sign-in, failed handshake) outranks everything else, then
  // anything up, then anything on its way up.
  readonly property string overallState: {
    var vpnState = installed ? displayState : "disconnected"
    if (!installed && !fzInstalled) return "missing"
    if (vpnState === "needs-auth" || vpnState === "failed") return vpnState
    if (vpnState === "connected" || fzDisplayState === "connected") return "connected"
    if (vpnState === "connecting" || fzDisplayState === "connecting") return "connecting"
    return "disconnected"
  }
  readonly property bool anyActive: (installed && active) || fzActive
  readonly property bool anyBusy: busy || fzBusy
  readonly property string defaultTunnel: String(setting("defaultTunnel", "auto")).trim().toLowerCase()

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 600)
  readonly property int connectTimeoutSec: intSetting("connectTimeoutSec", 30, 5, 120)
  readonly property string configuredProfile: Model.expandHome(String(setting("profile", "")), home)
  readonly property string profilesDir: Model.expandHome(String(setting("profilesDir", "")), home)
  readonly property string dnsServer: String(setting("dnsServer", "")).trim()
  readonly property var dnsDomainList: Model.splitWords(setting("dnsDomains", ""))

  signal actionFinished(bool ok)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  // The configured profile wins; otherwise the first discovered one keeps the
  // switch useful on a fresh install. A property rather than a function alone,
  // so the rows that mark the default repaint the moment it changes.
  readonly property string activeProfile: {
    if (configuredProfile !== "") return configuredProfile
    if (profiles.length > 0) return profiles[0].path
    return ""
  }

  function defaultProfile() { return activeProfile }

  function searchDirs() {
    var dirs = []
    if (profilesDir !== "") dirs.push(profilesDir)
    if (configuredProfile !== "") {
      var parent = configuredProfile.substring(0, configuredProfile.lastIndexOf("/"))
      if (parent !== "" && dirs.indexOf(parent) === -1) dirs.push(parent)
    }
    // Downloads is where a profile a colleague sent you lands; the rest are
    // where one ends up once you have filed it.
    var fallbacks = [home + "/.config/openvpn", home + "/openvpn", home + "/vpn",
                     home + "/Downloads", "/etc/openvpn"]
    for (var i = 0; i < fallbacks.length; i++) {
      if (dirs.indexOf(fallbacks[i]) === -1) dirs.push(fallbacks[i])
    }
    return dirs
  }

  function refresh() {
    if (helperPath === "" || statusProcess.running) return
    refreshing = true
    statusProcess.command = [helperPath, "status"]
    statusProcess.running = true
  }

  function refreshProfiles() {
    if (helperPath === "" || profilesProcess.running) return
    profilesProcess.command = [helperPath, "profiles"].concat(searchDirs())
    profilesProcess.running = true
  }

  // Where the picker should open: whatever you are already pointed at, so the
  // first thing on screen is the folder you would have navigated to anyway.
  function browseStart() {
    if (browseDir !== "") return browseDir
    if (configuredProfile !== "") {
      var parent = configuredProfile.substring(0, configuredProfile.lastIndexOf("/"))
      if (parent !== "") return parent
    }
    if (profilesDir !== "") return profilesDir
    return home
  }

  function browse(dir) {
    var target = dir === undefined || dir === null ? "" : String(dir)
    if (helperPath === "") return
    if (browseProcess.running) {
      _queuedBrowse = target
      _hasQueuedBrowse = true
      return
    }
    browsing = true
    var args = [helperPath, "browse", target]
    if (browseHidden) args.push("--hidden")
    browseProcess.command = args
    browseProcess.running = true
  }

  function toggleHidden() {
    browseHidden = !browseHidden
    browse(browseDir)
  }

  // The widget's own settings live in shell.json, which the shell owns; the
  // helper hands the write to it over IPC and the bar patches this item's
  // `settings` back in place, without rebuilding the panel under your cursor.
  function saveSetting(key, value, message) {
    if (helperPath === "" || settingProcess.running) return
    lastError = ""
    _saveMessage = message || ""
    settingProcess.command = [helperPath, "set", String(key), String(value)]
    settingProcess.running = true
  }

  function chooseProfile(path) {
    if (!path) return
    var stored = Model.homeRelative(String(path), home)
    saveSetting("profile", stored, Model.baseName(String(path)) + " is now the default profile")
  }

  function chooseProfilesDir(dir) {
    if (!dir) return
    var stored = Model.homeRelative(String(dir), home)
    saveSetting("profilesDir", stored, "Scanning " + stored + " for profiles")
  }

  // An imported profile survives the file being moved or deleted, and is what
  // openvpn3 lists for every tool on the machine, not just this widget.
  function importProfile(path) {
    if (helperPath === "" || actionProcess.running || !path) return
    lastError = ""
    actionStatus = "Importing…"
    _reloadProfilesAfterAction = true
    actionProcess.command = [helperPath, "import", String(path)]
    actionProcess.running = true
  }

  function dnsArgs() {
    var args = []
    if (dnsServer !== "") args = args.concat(["--dns-server", dnsServer])
    for (var i = 0; i < dnsDomainList.length; i++) args = args.concat(["--dns-domain", dnsDomainList[i]])
    return args
  }

  function connectProfile(profilePath) {
    var target = profilePath && profilePath !== "" ? profilePath : defaultProfile()
    if (target === "") {
      lastError = "No VPN profile configured — pick one in the widget settings"
      return
    }
    if (helperPath === "" || actionProcess.running) return
    lastError = ""
    actionStatus = "Connecting…"
    _autoOpenAuth = true
    _desired = 1
    actionProcess.command = [helperPath, "connect", target, "--timeout", String(connectTimeoutSec)].concat(dnsArgs())
    actionProcess.running = true
  }

  function disconnectAll() {
    if (helperPath === "" || actionProcess.running) return
    lastError = ""
    actionStatus = "Disconnecting…"
    _desired = 0
    actionProcess.command = [helperPath, "disconnect", "--all"]
    actionProcess.running = true
  }

  function disconnectSession(sessionPath) {
    if (helperPath === "" || actionProcess.running || !sessionPath) return
    lastError = ""
    actionStatus = "Disconnecting…"
    if (sessions.length <= 1) _desired = 0
    actionProcess.command = [helperPath, "disconnect", String(sessionPath)]
    actionProcess.running = true
  }

  // What the main switch dials: the setting when it names a client that is
  // there, otherwise openvpn3 when it has a profile, otherwise Firezone.
  function switchTarget() {
    if (defaultTunnel === "firezone" && fzInstalled) return "firezone"
    if (defaultTunnel === "openvpn" && installed) return "openvpn"
    if (installed && activeProfile !== "") return "openvpn"
    if (fzInstalled) return "firezone"
    return "openvpn"
  }

  // The switch reads "on" while anything is up, so turning it off takes down
  // everything, whichever client it belongs to.
  function toggleTunnel() {
    if (anyBusy) return
    if (needsAuth) { openAuthUrl(); return }
    if (anyActive) { disconnectEverything(); return }
    if (switchTarget() === "firezone") firezoneConnect()
    else connectProfile("")
  }

  function disconnectEverything() {
    if (installed && (active || sessions.length > 0)) disconnectAll()
    if (fzActive) firezoneDisconnect()
  }

  function firezoneConnect() {
    if (helperPath === "" || firezoneProcess.running || !fzInstalled) return
    fzError = ""
    actionStatus = firezone.state === "stopped" ? "Starting Firezone…" : "Connecting Firezone…"
    fzSignInPending = false
    _fzDesired = 1
    firezoneProcess.command = [helperPath, "firezone-connect", "--timeout", String(connectTimeoutSec)]
    firezoneProcess.running = true
  }

  function firezoneDisconnect() {
    if (helperPath === "" || firezoneProcess.running || !fzInstalled) return
    fzError = ""
    actionStatus = "Disconnecting Firezone…"
    fzSignInPending = false
    _fzDesired = 0
    firezoneProcess.command = [helperPath, "firezone-disconnect"]
    firezoneProcess.running = true
  }

  // The sign-in itself happens in Firezone's own window (Entra ID in the
  // browser, handed back to the app); all we can do is bring that window up.
  function firezoneSignIn() {
    if (helperPath === "" || firezoneProcess.running || !fzInstalled) return
    fzError = ""
    firezoneProcess.command = [helperPath, "firezone-signin"]
    firezoneProcess.running = true
  }

  // One click on the Firezone row: whatever moves it forward.
  function firezoneActivate() {
    if (fzBusy) return
    if (fzDisplayState === "signed-out") firezoneSignIn()
    else if (fzActive) firezoneDisconnect()
    else firezoneConnect()
  }

  // Qt.openUrlExternally goes through QDesktopServices inside the shell
  // process; omarchy-launch-browser is what the rest of Omarchy uses, and it
  // resolves the default browser, detaches, and focuses the window.
  function openAuthUrl() {
    if (authUrl === "") { reconnect(); return }
    Quickshell.execDetached(["omarchy-launch-browser", authUrl])
    actionStatus = "Opened the sign-in page"
    actionStatusTimer.restart()
  }

  // openvpn3 hands out a sign-in URL once per session, so getting a fresh one
  // means dropping the parked session and starting over.
  function reconnect() {
    var target = defaultProfile()
    if (target === "") {
      lastError = "No VPN profile configured — pick one in the widget settings"
      return
    }
    if (helperPath === "" || actionProcess.running) return
    lastError = ""
    authUrl = ""
    actionStatus = "Reconnecting…"
    _autoOpenAuth = true
    _desired = 1
    actionProcess.command = [helperPath, "reconnect", target, "--timeout", String(connectTimeoutSec)].concat(dnsArgs())
    actionProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.error || "Could not read the openvpn3 status"
      return
    }
    installed = parsed.installed
    tunnelState = parsed.state
    activePath = parsed.activePath
    authUrl = parsed.authUrl
    sessions = parsed.sessions
    device = parsed.device
    ipv4 = parsed.ipv4
    dnsServers = parsed.dns
    dnsDomains = parsed.domains
    bytesIn = parsed.bytesIn
    bytesOut = parsed.bytesOut
    firezone = parsed.firezone
    if (firezone.state === "connected") fzSignInPending = false
    if (_fzDesired === 1 && firezone.state === "connected") _fzDesired = -1
    if (_fzDesired === 0 && firezone.state !== "connected" && firezone.state !== "connecting") _fzDesired = -1
    if (firezone.state === "connected") fzError = ""
    lastError = parsed.error
    // Reality caught up with the pending connect/disconnect — stop overriding.
    if (_desired === 1 && tunnelState === "connected") _desired = -1
    if (_desired === 0 && tunnelState === "disconnected") _desired = -1
    // Neither of those will ever arrive while the session waits for a sign-in
    // or after the handshake failed, so let go of the optimistic state.
    if (tunnelState === "needs-auth" || tunnelState === "failed") _desired = -1
    if (_autoOpenAuth && tunnelState === "needs-auth" && authUrl !== "") {
      _autoOpenAuth = false
      openAuthUrl()
    }
    if (tunnelState !== "needs-auth") _autoOpenAuth = false
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  Component.onCompleted: {
    refresh()
    refreshProfiles()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // Uptime and transfer counters tick without hammering openvpn3.
    id: clockTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    id: profilesTimer
    interval: 300000
    repeat: true
    running: true
    onTriggered: root.refreshProfiles()
  }

  Timer {
    // openvpn3 needs a few seconds to settle after connect/disconnect, so poll
    // a handful of times instead of waiting for the next periodic refresh.
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      ticks += 1
      root.refresh()
      if (ticks >= 6) {
        ticks = 0
        running = false
        root._desired = -1
        root._fzDesired = -1
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode === 0) root.applyStatus(statusStdout.text)
      else root.lastError = root.elide(statusStderr.text || statusStdout.text || "openvpn3 status failed")
    }
  }

  Process {
    id: profilesProcess
    running: false
    command: []
    stdout: StdioCollector { id: profilesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.profiles = Model.parseProfiles(profilesStdout.text)
    }
  }

  Process {
    id: browseProcess
    running: false
    command: []
    stdout: StdioCollector { id: browseStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.browsing = false
      if (exitCode === 0) {
        var parsed = Model.parseBrowse(browseStdout.text)
        if (parsed.ok) {
          root.browseDir = parsed.dir
          root.browseParent = parsed.parent
          root.browseEntries = parsed.entries
          root.browseTruncated = parsed.truncated
        }
        root.browseError = parsed.error
      } else {
        root.browseError = "Could not read that folder"
      }
      if (root._hasQueuedBrowse) {
        var next = root._queuedBrowse
        root._hasQueuedBrowse = false
        root._queuedBrowse = ""
        root.browse(next)
      }
    }
  }

  Process {
    id: settingProcess
    running: false
    command: []
    stdout: StdioCollector { id: settingStdout; waitForEnd: true }
    stderr: StdioCollector { id: settingStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(settingStdout.text)
      if (exitCode === 0 && result.ok) {
        root.actionStatus = root._saveMessage
        if (root.actionStatus !== "") actionStatusTimer.restart()
        // The setting is what decides which profiles are worth listing.
        root.refreshProfiles()
      } else {
        root.lastError = root.elide(result.message || settingStderr.text || "Could not save the setting")
      }
      root._saveMessage = ""
    }
  }

  Process {
    id: firezoneProcess
    running: false
    command: []
    stdout: StdioCollector { id: firezoneStdout; waitForEnd: true }
    stderr: StdioCollector { id: firezoneStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(firezoneStdout.text)
      if (exitCode === 0 && result.ok) {
        // The helper says "Sign in…" when it opened the Firezone window instead
        // of connecting; there is nothing to wait for until you do.
        if (result.message.indexOf("Sign in") === 0) {
          root.fzSignInPending = true
          root._fzDesired = -1
        }
        root.actionStatus = result.message !== "" ? root.elide(result.message) : ""
        root.fzError = ""
      } else {
        root._fzDesired = -1
        root.fzError = root.elide(result.message || firezoneStderr.text || "firezone command failed")
        root.actionStatus = ""
      }
      if (root.actionStatus !== "") actionStatusTimer.restart()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
      root.actionFinished(exitCode === 0 && result.ok)
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parseResult(actionStdout.text)
      // The refresh below re-reads the URL from openvpn3 and opens it; taking
      // it from here too would open the browser twice.
      if (result.authUrl !== "") root.authUrl = result.authUrl
      if (exitCode === 0 && result.ok) {
        // A message on a successful action means the tunnel came up but
        // something secondary did not, such as the DNS wiring.
        root.actionStatus = result.message !== "" ? root.elide(result.message) : ""
        root.lastError = ""
      } else {
        root._desired = -1
        root.lastError = root.elide(result.message || actionStderr.text || "openvpn3 command failed")
        root.actionStatus = ""
      }
      if (root.actionStatus !== "") actionStatusTimer.restart()
      if (root._reloadProfilesAfterAction) {
        root._reloadProfilesAfterAction = false
        root.refreshProfiles()
      }
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
      root.actionFinished(exitCode === 0 && result.ok)
    }
  }
}
