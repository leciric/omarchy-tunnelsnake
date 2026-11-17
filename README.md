<p align="center"><img src="logo.svg" width="128" alt="Tunnelsnake logo"></p>

# Tunnelsnake

An [Omarchy](https://omarchy.org) bar widget for OpenVPN 3 and
[Firezone](https://www.firezone.dev). It shows whether a tunnel is up, connects
and disconnects with one click, and lists every running session — the same
things `vpnstart` / `vpnstop` / `vpnstatus` do in a shell, without the shell.

- **Bar icon** — a tunnel mouth that fills in when a session is connected,
  pulses while one is being negotiated, and carries a count badge when more
  than one tunnel is up.
- **Panel** — an on/off switch, the live interface, address, DNS, search
  domains and transfer counters, every running session with a per-session
  disconnect, and every profile you can dial.
- **File picker** — walk to your `.ovpn` file wherever it lives and make it
  the profile the switch connects to. No editing config files to get started.
- **Firezone** — drives the official Firezone client instead of openvpn3:
  connect, disconnect, and sign in. The widget runs one client at a time, with
  a picker in the panel when both are installed.
- **DNS wiring** — optionally pins a DNS server and search domains on the tun
  device right after connecting, which is what split-DNS setups (AKS private
  link, internal zones) need.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- At least one of:
  - `openvpn3` — it lives in the AUR, so `yay -S openvpn3`, not `omarchy pkg add`
  - the Firezone GUI client, 1.5.19 or later — `yay -S firezone-client-gui-bin`
    (see [Firezone](#firezone) for the two steps the AUR package skips)
- `systemd-resolved` — for the DNS settings, and always for Firezone

## Install

```bash
omarchy plugin add https://github.com/leciric/omarchy-tunnelsnake.git
omarchy plugin enable linting.tunnelsnake --section right
```

Then click the tunnel icon, pick **Choose a profile file…** at the bottom of
the panel, and walk to your `.ovpn`. That is the whole setup — everything
below is for people who want to tune it.

## Picking a profile

The panel lists every profile it can find: `.ovpn` and `.conf` files in the
folders it scans, plus anything already imported into openvpn3. When yours is
somewhere else, the last row of the **PROFILES** section opens a file picker.

| In the picker | What happens |
|---------------|--------------|
| A folder | Walks into it |
| `..` | Walks back out |
| A profile | Becomes the profile the switch connects to |
| 󰋺 on a profile | Imports it into openvpn3, so it survives the file moving |
| **Scan this folder for profiles** | Lists every profile in it, so you can switch between them |
| ↑ ↓ | Move · ← → leave and enter a folder · Enter take · `.` show dot-folders · Esc back |

Picking writes the choice into `~/.config/omarchy/shell.json` through the
shell, the same way `omarchy bar set` does — so it survives restarts and there
is nothing to edit by hand.

Without any picking at all, the widget scans `~/.config/openvpn`, `~/openvpn`,
`~/vpn`, `~/Downloads` and `/etc/openvpn`, which covers the common case of a
profile a colleague just sent you.

## Settings

Everything the picker writes can also be set by hand, on the widget's entry in
`~/.config/omarchy/shell.json` or with `omarchy bar set linting.tunnelsnake
<key> <value>`:

| Key | What it does |
|-----|--------------|
| `profile` | The profile the switch connects to. Empty means "the first profile found". |
| `profilesDir` | Folder scanned for profiles, on top of the ones always scanned. |
| `client` | The one client the widget drives: `openvpn`, `firezone`, or `auto` (openvpn3 when installed, Firezone otherwise). The panel's picker writes this. |
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
| `c` / `d` / `r` in the panel | Connect, disconnect everything, refresh (for the chosen client) |
| `f` in the panel | Open the file picker |
| ← → on the picker | Switch between OpenVPN and Firezone |
| ↑ ↓ + Enter | Move through sessions and profiles; Enter does what clicking the row does |

Clicking a session disconnects it. Clicking a profile connects it, or
disconnects it if it is the one already running. 󰐃 on a profile makes it the
default without connecting to it.

## Firezone

The widget drives one client at a time. When both openvpn3 and the `firezone`
CLI (it ships with the GUI client) are installed, the panel shows an
**OpenVPN | Firezone** picker under the switch. Picking one saves it as the
`client` setting and takes the other client's tunnel down, so only one is
ever up. With just one of them installed there is no picker.

With Firezone picked, the panel shows a single **FIREZONE** row: the account,
the `tun-firezone` address and who you are signed in as. The switch, the row,
`c` / `d` and a middle click on the bar icon all act on it. Clicking does
whatever moves it forward:

| Firezone says | A click |
|---------------|---------|
| App not running | Starts the Firezone app, then connects |
| Not connected | Connects with the stored sign-in |
| No sign-in stored | Opens the Firezone window; sign in there |
| Connected | Disconnects, keeping the sign-in |

The tunnel itself runs in Firezone's root service, which only takes orders
from the Firezone app, and the `firezone` CLI talks to the app. That is why a
connect starts the app first, and why the sign-in happens in its window:
pointing it at your server (Settings → Advanced, Settings → General → Account
slug) is a one-time job done there, not here.

Picking from a script or a keybinding:

```bash
omarchy-shell linting.tunnelsnake use firezone   # or: use openvpn
```

### Two things the AUR package does not do

`firezone-client-gui-bin` repackages the official `.deb` but skips its
post-install script, so do by hand what it would have done, then log out and
back in:

```bash
sudo usermod -aG firezone-client "$USER"
sudo systemctl enable --now firezone-client-tunnel.service
```

### "no IP addresses available"

Firezone learns your upstream DNS servers from `resolvectl dns` and needs each
one to be a plain address. Omarchy configures systemd-resolved with global
DNS-over-TLS servers only, written `1.1.1.1#cloudflare-dns.com`. Firezone
cannot read those, decides there is no DNS at all ("No system default DNS
servers available" in `journalctl -u firezone-client-tunnel`), cannot resolve
its own portal, and gives up with "no IP addresses available".

The panel warns about this before you connect. The fix is to give your network
link a plain DNS server, through whatever configures it (DHCP via
systemd-networkd or NetworkManager, say). To confirm the diagnosis first,
`resolvectl dns <link> 1.1.1.1 1.0.0.1` does it until the link is next
reconfigured.

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
omarchy-shell linting.tunnelsnake status       # connected | connecting | needs-auth | failed | disconnected, for the chosen client
omarchy-shell linting.tunnelsnake client       # openvpn | firezone
omarchy-shell linting.tunnelsnake use firezone # switch clients, taking the other one down
omarchy-shell linting.tunnelsnake profile      # the profile the switch would dial
omarchy-shell linting.tunnelsnake connect      # the chosen client
omarchy-shell linting.tunnelsnake disconnect
omarchy-shell linting.tunnelsnake firezone            # connected | connecting | disconnected | signed-out | stopped | missing
omarchy-shell linting.tunnelsnake firezoneConnect
omarchy-shell linting.tunnelsnake firezoneDisconnect
omarchy-shell linting.tunnelsnake firezoneSignin      # bring up the Firezone window
omarchy-shell linting.tunnelsnake reconnect    # fresh sign-in link
omarchy-shell linting.tunnelsnake signin       # reopen the sign-in page
omarchy-shell linting.tunnelsnake pick         # open the file picker
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
| `Panel.qml` | The popup: hero, session list, profile list, file picker, keyboard navigation |
| `Service.qml` | Polling, optimistic connect/disconnect state, process plumbing |
| `Model.js` | Parsing and formatting helpers, no QML dependencies |
| `TunnelIcon.qml` | The drawn icon |
| `bin/tunnelsnake` | Every openvpn3 and firezone call and every disk walk, answering in JSON |

Nothing in the QML shells out to `openvpn3` or `firezone` directly — `bin/tunnelsnake` owns
that, which is what makes the whole thing testable:

```bash
tests/run.sh                                    # parser tests against a fake openvpn3 and firezone
bin/tunnelsnake --help                          # every subcommand
bin/tunnelsnake status | jq                     # what the widget actually sees
bin/tunnelsnake browse ~/vpn | jq               # what the picker actually sees
/usr/lib/qt6/bin/qmllint *.qml                  # the Qt 6 qmllint, not Qt 5's
omarchy plugin validate .
```

Writing a setting is the one thing the helper does not do itself: it hands the
value to the running shell over IPC (`omarchy-shell shell setBarWidget`), which
owns `shell.json` and patches the live widget in place, so the panel does not
get rebuilt under your cursor.

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
