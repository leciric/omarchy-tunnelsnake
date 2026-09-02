#!/usr/bin/env bash
# Exercises bin/tunnelsnake against tests/fake-openvpn3 so the output parsing
# can be checked without a real VPN. Run: tests/run.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname "$here")
export TUNNELSNAKE_OPENVPN3="$here/fake-openvpn3"
snake="$root/bin/tunnelsnake"

pass=0
fail=0

check() {
  local label=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    printf '  ok   %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

echo "status, no sessions"
out=$(TUNNELSNAKE_FAKE_STATE=none "$snake" status)
check "is valid JSON"        "ok"           "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo ok)"
check "state"                "disconnected" "$(jq -r .state <<<"$out")"
check "session count"        "0"            "$(jq -r .sessionCount <<<"$out")"
check "openvpn3 detected"    "true"         "$(jq -r .installed <<<"$out")"

echo "status, two sessions"
out=$(TUNNELSNAKE_FAKE_STATE=up "$snake" status)
check "is valid JSON"        "ok"                                          "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo ok)"
check "state"                "connected"                                   "$(jq -r .state <<<"$out")"
check "session count"        "2"                                           "$(jq -r .sessionCount <<<"$out")"
check "active session wins"  "/net/openvpn/v3/sessions/2f1c9e2ds4b1as9e12" "$(jq -r .activePath <<<"$out")"
check "config strips parens" "/home/lint/vpn/work.ovpn"                     "$(jq -r '.sessions[0].config' <<<"$out")"
check "config path variant"  "backup.ovpn"                                 "$(jq -r '.sessions[1].config' <<<"$out")"
check "device off owner row" "tun0"                                        "$(jq -r '.sessions[0].device' <<<"$out")"
check "created drops PID"    "2026-08-20 09:14:02"                         "$(jq -r '.sessions[0].created' <<<"$out")"
check "owner drops device"   "lint"                                        "$(jq -r '.sessions[0].owner' <<<"$out")"
check "second is connecting" "connecting"                                  "$(jq -r '.sessions[1].state' <<<"$out")"
check "transfer counters"    "1048576"                                     "$(jq -r '.stats.BYTES_IN' <<<"$out")"
check "no url when connected" "null"                                       "$(jq -r .authUrl <<<"$out")"

echo "status, waiting on web sign-in"
out=$(TUNNELSNAKE_FAKE_STATE=auth "$snake" status)
check "state"                "needs-auth" "$(jq -r .state <<<"$out")"
check "no device yet"        ""           "$(jq -r '.sessions[0].device' <<<"$out")"
check "sign-in url"          "https://sso.example.com/saml/redirect/?RelayState=vpnauth~~abc123" "$(jq -r .authUrl <<<"$out")"
check "url on the session"   "https://sso.example.com/saml/redirect/?RelayState=vpnauth~~abc123" "$(jq -r '.sessions[0].authUrl' <<<"$out")"

echo "status, failed handshake"
out=$(TUNNELSNAKE_FAKE_STATE=failed "$snake" status)
# "Client authentication failed" must not be mistaken for "waiting on auth".
check "state"                "failed"     "$(jq -r .state <<<"$out")"

echo "session titles"
# Model.js turns the config field into the row title; the helper must hand it
# the raw value, path and all, for that to be possible.
out=$(TUNNELSNAKE_FAKE_STATE=up "$snake" status)
check "keeps full path"      "/home/lint/vpn/work.ovpn" "$(jq -r '.sessions[0].config' <<<"$out")"

echo "profiles"
tmp=$(mktemp -d)
mkdir -p "$tmp/nested"
touch "$tmp/office.ovpn" "$tmp/notes.txt" "$tmp/nested/branch.conf"
out=$("$snake" profiles "$tmp")
names=$(jq -r '[.profiles[] | select(.kind == "file") | .name] | sort | join(",")' <<<"$out")
check "profiles found"       "branch,office" "$names"
check "non-profile ignored"  "2"             "$(jq -r '[.profiles[] | select(.kind == "file")] | length' <<<"$out")"
# The same folder named twice, and once through its own parent, is still one
# set of profiles.
out=$("$snake" profiles "$tmp" "$tmp" "$tmp/nested")
check "duplicates collapsed" "2"          "$(jq -r '[.profiles[] | select(.kind == "file")] | length' <<<"$out")"

echo "imported profiles"
# openvpn3 v27 answers configs-list in JSON; the name is the only field that
# survives a profile name with a space in it.
out=$("$snake" profiles)
check "imported name"        "work"                      "$(jq -r '[.profiles[] | select(.kind == "imported")][0].name' <<<"$out")"
check "imported dbus path"   "/net/openvpn/v3/configuration/aa11" "$(jq -r '[.profiles[] | select(.kind == "imported")][0].path' <<<"$out")"
check "name with a space"    "site b"                    "$(jq -r '[.profiles[] | select(.kind == "imported")][1].name' <<<"$out")"
check "invalid config flagged" "false"                   "$(jq -r '[.profiles[] | select(.kind == "imported")][1].valid' <<<"$out")"
# An openvpn3 without --json still has to work: the verbose table carries the
# same two fields.
out=$(TUNNELSNAKE_FAKE_CONFIGS=legacy "$snake" profiles)
check "legacy imported name" "work"                      "$(jq -r '[.profiles[] | select(.kind == "imported")][0].name' <<<"$out")"
check "legacy space in name" "site b"                    "$(jq -r '[.profiles[] | select(.kind == "imported")][1].name' <<<"$out")"
check "legacy invalid flag"  "false"                     "$(jq -r '[.profiles[] | select(.kind == "imported")][1].valid' <<<"$out")"

echo "browse"
room=$(mktemp -d)
mkdir -p "$room/.hidden" "$room/sub"
touch "$room/office.ovpn" "$room/notes.txt"
out=$("$snake" browse "$room")
check "is valid JSON"        "ok"          "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo ok)"
check "folders come first"   "dir"         "$(jq -r '.entries[0].kind' <<<"$out")"
check "dot-folders hidden"   "sub"         "$(jq -r '[.entries[] | select(.kind == "dir") | .name] | join(",")' <<<"$out")"
check "profile listed"       "office.ovpn" "$(jq -r '[.entries[] | select(.kind == "file")][0].name' <<<"$out")"
check "notes.txt ignored"    "1"           "$(jq -r '[.entries[] | select(.kind == "file")] | length' <<<"$out")"
check "parent offered"       "$(dirname "$room")" "$(jq -r .parent <<<"$out")"
out=$("$snake" browse "$room" --hidden)
check "dot-folders on ask"   ".hidden,sub" "$(jq -r '[.entries[] | select(.kind == "dir") | .name] | join(",")' <<<"$out")"
out=$("$snake" browse /)
check "root has no parent"   "null"        "$(jq -r .parent <<<"$out")"
out=$("$snake" browse "$room/does-not-exist")
check "missing folder falls home" "$HOME"  "$(jq -r .dir <<<"$out")"
out=$(TUNNELSNAKE_BROWSE_LIMIT=1 "$snake" browse "$room")
check "long listing capped"  "true"        "$(jq -r .truncated <<<"$out")"

echo "import"
out=$("$snake" import "$room/office.ovpn")
check "import ok"            "true"        "$(jq -r .ok <<<"$out")"
check "import says so"       "office imported into openvpn3" "$(jq -r .message <<<"$out")"
out=$(TUNNELSNAKE_FAKE_IMPORT=warn "$snake" import "$room/office.ovpn")
check "warning passed on"    "Configuration profile is missing required options: --ca" "$(jq -r .message <<<"$out")"
out=$(TUNNELSNAKE_FAKE_IMPORT=fail "$snake" import "$room/office.ovpn")
check "import failure"       "false"       "$(jq -r .ok <<<"$out")"
out=$("$snake" import "$room/nope.ovpn")
check "import missing file"  "false"       "$(jq -r .ok <<<"$out")"
rm -rf "$tmp" "$room"

echo "settings"
# No key at all is the one failure the widget can hit without a running shell.
out=$("$snake" set)
check "set needs a key"      "false"      "$(jq -r .ok <<<"$out")"
check "set says why"         "No setting name given" "$(jq -r .message <<<"$out")"
# A widget that is not on the bar has nowhere to keep settings; the shell says
# so in its own words, and the helper translates them into an instruction.
out=$(TUNNELSNAKE_WIDGET_ID=tunnelsnake.not-installed "$snake" set profile /tmp/x.ovpn)
check "set off the bar"      "false"      "$(jq -r .ok <<<"$out")"
case "$(jq -r .message <<<"$out")" in
  "Tunnelsnake is not on the bar"*|"omarchy-shell"*)
    check "set explains itself" "ok" "ok" ;;
  *)
    check "set explains itself" "ok" "$(jq -r .message <<<"$out")" ;;
esac

echo "actions"
out=$(TUNNELSNAKE_FAKE_STATE=up "$snake" disconnect --all)
check "disconnect all ok"    "true"  "$(jq -r .ok <<<"$out")"
out=$(TUNNELSNAKE_FAKE_STATE=none "$snake" disconnect --all)
check "nothing to disconnect" "No active sessions" "$(jq -r .message <<<"$out")"
out=$("$snake" connect "")
check "connect without profile" "false" "$(jq -r .ok <<<"$out")"
out=$("$snake" connect /nope/missing.ovpn)
check "connect with bad path"   "false" "$(jq -r .ok <<<"$out")"

tmp=$(mktemp -d)
touch "$tmp/work.ovpn"
out=$(TUNNELSNAKE_FAKE_STATE=auth "$snake" connect "$tmp/work.ovpn" --timeout 2)
check "sign-in url captured"     "https://sso.example.com/saml/redirect/?RelayState=vpnauth~~abc123" "$(jq -r .authUrl <<<"$out")"
check "does not wait for device" "Sign-in required to finish connecting" "$(jq -r .message <<<"$out")"
rm -rf "$tmp"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
((fail == 0))
