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
touch "$tmp/office.ovpn" "$tmp/notes.txt"
out=$("$snake" profiles "$tmp")
check "file profile found"   "office"     "$(jq -r '[.profiles[] | select(.kind == "file")][0].name' <<<"$out")"
check "non-ovpn ignored"     "1"          "$(jq -r '[.profiles[] | select(.kind == "file")] | length' <<<"$out")"
check "imported profile"     "work.ovpn"  "$(jq -r '[.profiles[] | select(.kind == "imported")][0].name' <<<"$out")"
rm -rf "$tmp"

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
