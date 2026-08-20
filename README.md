# Tunnelsnake

An [Omarchy](https://omarchy.org) bar widget for OpenVPN 3. It shows whether a
tunnel is up, connects and disconnects with one click, and lists every running
session — the same things `vpnstart` / `vpnstop` / `vpnstatus` do in a shell,
without the shell.

- **Bar icon** — a tunnel mouth that fills in when a session is connected,
  pulses while one is being negotiated, and carries a count badge when more
  than one tunnel is up.
- **Panel** — an on/off switch, the live interface, address, DNS, search
  domains and transfer counters, every running session with a per-session
  disconnect, and every profile you can dial.
- **DNS wiring** — optionally pins a DNS server and search domains on the tun
  device right after connecting, which is what split-DNS setups (AKS private
  link, internal zones) need.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- `openvpn3` (`omarchy pkg add openvpn3`)
- `systemd-resolved` — only if you use the DNS settings

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-tunnelsnake.git
omarchy plugin enable linting.tunnelsnake --section right
```

Or, working from a clone:

```bash
ln -sfn ~/www/personal/omarchy-tunnelsnake ~/.config/omarchy/plugins/linting.tunnelsnake
omarchy-shell shell rescanPlugins
omarchy plugin enable linting.tunnelsnake --section right
```

## Settings

Set these in the widget's settings panel, or directly on its entry in
`~/.config/omarchy/shell.json`:

| Key | What it does |
|-----|--------------|
| `profile` | The `.ovpn` file the switch connects to. Empty means "the first profile found". |
| `profilesDir` | Folder scanned for `.ovpn` files. `~/.config/openvpn`, `~/openvpn` and `~/vpn` are always scanned too, along with anything already imported into openvpn3. |
| `dnsServer` | Optional DNS server pinned on the tun device after connecting. |
| `dnsDomains` | Optional search domains, space separated. A `~` prefix routes only that domain through the tunnel. |
| `refreshIntervalSec` | How often openvpn3 is polled. Default 15. |
| `connectTimeoutSec` | How long to wait for the tun device before giving up. Default 30. |
| `hideWhenIdle` | Keep the icon out of the bar until a tunnel is up. Default false. |

```json
{
  "id": "linting.tunnelsnake",
  "profile": "~/vpn/work.ovpn",
  "profilesDir": "~/vpn",
  "dnsServer": "10.0.0.10",
  "dnsDomains": "~internal.example.com ~example.local"
}
```

## Using it

| Action | Result |
|--------|--------|
| Left click | Open the panel |
| Middle click | Connect or disconnect without opening anything |
| Right click | Force a refresh |
| `c` / `d` / `r` in the panel | Connect, disconnect everything, refresh |
| ↑ ↓ + Enter | Move through sessions and profiles; Enter disconnects a session or connects a profile |

Clicking a session disconnects it. Clicking a profile connects it, or
disconnects it if it is the one already running.

## SSO / web sign-in profiles

`openvpn3 session-start --background` does not print the sign-in URL — it only
reports that the session is running, and the session then parks on "Web
authentication required to connect". The URL lives in `openvpn3 session-auth`
for as long as the session waits there, so that is where the widget reads it
from on every poll. Connecting opens your browser once by itself; if you lose
the tab, the panel's sign-in row reopens the same URL. A parked session cannot
hand out a second URL, so **Reconnect** drops it and starts over for a fresh
link.

## Scripting it

```bash
omarchy-shell linting.tunnelsnake status       # connected | connecting | needs-auth | failed | disconnected
omarchy-shell linting.tunnelsnake connect
omarchy-shell linting.tunnelsnake disconnect
omarchy-shell linting.tunnelsnake reconnect    # fresh sign-in link
omarchy-shell linting.tunnelsnake signin       # reopen the sign-in page
omarchy-shell linting.tunnelsnake toggle       # the panel, not the tunnel
```

## About the DNS prompt

Pinning DNS on a link is a privileged operation, so `systemd-resolved` asks
polkit and Omarchy's polkit agent prompts you once per connect (the answer is
cached for a few minutes). No `sudo` and no root helper is involved; if the
unprivileged call fails outright, the helper retries once under `pkexec`.

## How it is put together

| File | Role |
|------|------|
| `BarWidget.qml` | The bar button and icon; injects `bar`/`settings`/`anchorItem` into the panel |
| `Panel.qml` | The popup: hero, session list, profile list, keyboard navigation |
| `Service.qml` | Polling, optimistic connect/disconnect state, process plumbing |
| `Model.js` | Parsing and formatting helpers, no QML dependencies |
| `TunnelIcon.qml` | The drawn icon |
| `bin/tunnelsnake` | Every openvpn3 call, answering in JSON |

Nothing in the QML shells out to `openvpn3` directly — `bin/tunnelsnake` owns
that, which is what makes the whole thing testable:

```bash
tests/run.sh                              # parser tests against a fake openvpn3
bin/tunnelsnake status | jq               # what the widget actually sees
qmllint -I "$OMARCHY_PATH/shell" *.qml    # use the Qt 6 qmllint
omarchy plugin validate .
```

Two things to know while developing. `inotifywait` does not follow symlinks, so
a symlinked plugin never reports its own edits — re-create the symlink to fire
the watch. And a reload re-reads the manifest but keeps the already-compiled
QML, so code changes need a shell restart:

```bash
ln -sfn "$PWD" ~/.config/omarchy/plugins/linting.tunnelsnake   # manifest/script changes
omarchy restart shell                                          # QML changes
```

`bin/tunnelsnake` is re-executed on every poll, so changes there are live
immediately.

## Removing it

```bash
omarchy plugin disable linting.tunnelsnake
rm ~/.config/omarchy/plugins/linting.tunnelsnake
```

## License

MIT
