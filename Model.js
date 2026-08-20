// Pure helpers for Tunnelsnake: everything that turns helper-script JSON into
// something the panel can draw lives here, so Panel.qml stays layout and
// Service.qml stays process plumbing.
function safeParse(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

function parseStatus(raw) {
  var parsed = safeParse(raw)
  if (!parsed || typeof parsed !== "object") {
    return { ok: false, error: "Could not read the openvpn3 status" }
  }
  var sessions = Array.isArray(parsed.sessions) ? parsed.sessions : []
  var link = parsed.link && typeof parsed.link === "object" ? parsed.link : {}
  return {
    ok: true,
    installed: parsed.installed === true,
    state: String(parsed.state || "disconnected"),
    activePath: String(parsed.activePath || ""),
    authUrl: String(parsed.authUrl || ""),
    sessionCount: Number(parsed.sessionCount || sessions.length),
    sessions: sessions,
    device: String(link.device || ""),
    ipv4: String(link.ipv4 || ""),
    dns: Array.isArray(link.dns) ? link.dns : [],
    domains: Array.isArray(link.domains) ? link.domains : [],
    bytesIn: statsValue(parsed.stats, ["BYTES_IN", "bytes_in", "bytesIn"]),
    bytesOut: statsValue(parsed.stats, ["BYTES_OUT", "bytes_out", "bytesOut"]),
    error: parsed.error ? String(parsed.error) : ""
  }
}

function parseProfiles(raw) {
  var parsed = safeParse(raw)
  if (!parsed || !Array.isArray(parsed.profiles)) return []
  var out = []
  for (var i = 0; i < parsed.profiles.length; i++) {
    var p = parsed.profiles[i]
    if (!p || !p.path) continue
    out.push({
      kind: String(p.kind || "file"),
      id: String(p.id || p.path),
      name: String(p.name || p.path),
      path: String(p.path)
    })
  }
  return out
}

function parseResult(raw) {
  var parsed = safeParse(raw)
  if (!parsed || typeof parsed !== "object") return { ok: false, message: "" }
  return {
    ok: parsed.ok === true,
    device: String(parsed.device || ""),
    message: String(parsed.message || ""),
    authUrl: String(parsed.authUrl || "")
  }
}

// openvpn3 has renamed these counters across releases, so try every spelling
// we have seen before giving up.
function statsValue(stats, keys) {
  if (!stats || typeof stats !== "object") return 0
  for (var i = 0; i < keys.length; i++) {
    var value = stats[keys[i]]
    if (value !== undefined && value !== null && isFinite(Number(value))) return Number(value)
  }
  return 0
}

function formatBytes(bytes) {
  var n = Number(bytes || 0)
  if (!isFinite(n) || n <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (n >= 1024 && index < units.length - 1) {
    n = n / 1024
    index += 1
  }
  return (index === 0 ? Math.round(n) : n.toFixed(n < 10 ? 1 : 0)) + " " + units[index]
}

// openvpn3 prints "2026-08-20 11:49:34" on current releases and
// "Thu Aug 20 09:14:02 2026" on older ones; only the first needs a nudge to
// become something Date.parse handles the same way everywhere.
function uptimeText(created, nowMs) {
  var text = String(created || "")
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(text)) text = text.replace(" ", "T")
  var started = Date.parse(text)
  if (!isFinite(started)) return ""
  var seconds = Math.floor(((nowMs || Date.now()) - started) / 1000)
  if (seconds < 0) return ""
  if (seconds < 60) return seconds + "s"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h " + (minutes % 60) + "m"
  return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
}

function stateLabel(state, device) {
  switch (String(state)) {
    case "connected":    return device ? "Connected · " + device : "Connected"
    case "connecting":   return "Connecting…"
    case "needs-auth":   return "Sign-in required"
    case "failed":       return "Connection failed"
    case "paused":       return "Paused"
    case "missing":      return "openvpn3 not installed"
    case "disconnected": return "No tunnel"
    default:             return "Unknown state"
  }
}

// openvpn3 reports the config name as the full path when a session was started
// straight from a file, which is far too long for a row. Keep the file name.
function sessionTitle(session) {
  if (!session) return "Session"
  var name = String(session.config || "").split("/").pop().replace(/\.ovpn$/, "")
  if (name === "") name = String(session.name || "")
  if (name === "") name = shortPath(String(session.path || ""))
  return name
}

function sessionMeta(session, nowMs) {
  if (!session) return ""
  var parts = []
  if (session.device) parts.push(String(session.device))
  var up = uptimeText(session.created, nowMs)
  if (up !== "") parts.push("up " + up)
  var status = String(session.status || "")
  // "Connection, Client connected" -> "Client connected"
  var comma = status.indexOf(",")
  if (comma !== -1) status = status.substring(comma + 1).trim()
  if (status !== "") parts.push(status)
  return parts.join(" · ")
}

function shortPath(path) {
  var parts = String(path || "").split("/")
  var tail = parts[parts.length - 1] || ""
  return tail.length > 10 ? tail.substring(0, 10) + "…" : tail
}

function profileLabel(profile) {
  if (!profile) return ""
  return String(profile.name || "").replace(/\.ovpn$/, "")
}

function profileMeta(profile, home) {
  if (!profile) return ""
  if (profile.kind === "imported") return "imported into openvpn3"
  return homeRelative(String(profile.path || ""), home)
}

function homeRelative(path, home) {
  var value = String(path || "")
  var root = String(home || "")
  if (root !== "" && value.indexOf(root + "/") === 0) return "~/" + value.substring(root.length + 1)
  return value
}

// A session and a profile refer to the same tunnel when the file name matches
// the config name openvpn3 recorded when the session started.
function isProfileActive(profile, sessions) {
  if (!profile || !Array.isArray(sessions)) return false
  var name = String(profile.name || "").replace(/\.ovpn$/, "")
  var file = String(profile.path || "").split("/").pop().replace(/\.ovpn$/, "")
  for (var i = 0; i < sessions.length; i++) {
    var config = String(sessions[i].config || "").replace(/\.ovpn$/, "")
    if (config !== "" && (config === name || config === file)) return true
    if (String(sessions[i].configPath || "") === String(profile.path || "")) return true
  }
  return false
}

function splitWords(value) {
  var out = []
  var parts = String(value || "").split(/[\s,]+/)
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] !== "") out.push(parts[i])
  }
  return out
}

function expandHome(path, home) {
  var value = String(path || "")
  var root = String(home || "")
  if (root === "") return value
  if (value === "~") return root
  if (value.indexOf("~/") === 0) return root + "/" + value.substring(2)
  return value
}
