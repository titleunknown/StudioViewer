# LfS Viewer (Mac app)

A menu bar app that runs the LfS Web Viewer for you: one-click start and stop, the addresses to
share (with QR codes), who may rate and tag, and notifications when something goes wrong.
Swift/SwiftUI, macOS 15+, Faini Made team (`T9V5W5P5J4`), bundle id `Faini-Made.LfS-Viewer`.

## Build

```sh
cd App
xcodebuild -project LfSViewer.xcodeproj -scheme "LfS Viewer" -configuration Debug build
```

Or open `LfSViewer.xcodeproj` in Xcode and press Run. The `LfSViewer/` source folder is
filesystem-synchronized: new `.swift` files dropped in are compiled without touching the project.

## How it fits together

The app doesn't reimplement the viewer. It bundles the same `lfs_viewer.py`, `viewer.html`,
`gate.html` and `remote-setup.html` from the folder above (the **Engine** group in Xcode references them, so there is one
copy), and runs the script as a child process:

```
python3 -I -u -B lfs_viewer.py --control --no-open --settings <Application Support>/LfS Viewer/settings.json --port 8787 [--local]
```

`--control` is the link: the script reports events on stdout (`@lfs {...}` lines) and takes
commands on stdin. Both are documented at the top of `lfs_viewer.py` under "Control". The script
stops when its stdin closes, so quitting (or a crash of) the app never leaves it running.

| File | What it does |
|---|---|
| `LfSViewerApp.swift` | The app (one hidden Settings scene that carries the app menu's About and Settings… commands), the app delegate that wires everything up, Dock icon handling. |
| `Windows.swift` | Opens the main, Acknowledgments and QR code windows as AppKit windows hosting SwiftUI, one of each, brought forward if already open. |
| `StatusMenu.swift` | The menu bar icon and menu, in AppKit: switch rows (SwiftUI in menu items) for the viewer and for remote sharing, as in Tailscale's menu, then Open Viewer in Browser, Addresses (copy, QR code, open), Open LfS Viewer Window, Quit. |
| `Engine.swift` | Starts/stops the script, reads its events, sends commands; the models it reports. |
| `Python.swift` | Which Python to use; where settings live; UserDefaults keys. |
| `MainWindow.swift` | The window: top bar with status and Start/Stop, then a sidebar of panels (`Panel`: Addresses, Viewers, Remote Sharing, Ratings & Tags, Settings, Log, About). `Navigation` holds the chosen panel, so the app menu's About/Settings… (⌘,) open the window on that panel. Also the Addresses, Ratings & Tags and Log panels, and `sectionFooter()` for the panels' left-aligned footers. |
| `Addresses.swift` | Address labels ("Wi-Fi (en0)"), copy/open, the QR code view (with "Open in fullscreen mode"). |
| `Notifier.swift` | Notifications: Capture One not answering (after 10 s), viewer crashed (with Restart), code guessing, remote sharing dropped/back/stopped. |
| `SettingsView.swift` | The Settings panel: startup, login item, Dock, port (**Use Port** checks it is 1024-65535 and not the tunnel port, then restarts the viewer on it; an orange note, also under Addresses, says when the viewer had to take another port), "only this Mac", tunnel port, how visitors' pages name you ("Visitors see you as": the photographer, the digi-tech… or your own words), notifications. (No separate Settings window: ⌘, opens this panel.) |
| `PipeLines.swift` | Reads the viewer's and cloudflared's output line by line (readabilityHandler). Replaced a `FileHandle.bytes.lines` loop that once stopped reading while the viewer ran on, which froze the window's updates. |
| `Tunnel.swift` | Remote sharing: runs cloudflared, watches its connections, the token in the Keychain. |
| `CloudflaredUpdate.swift` | The cloudflared row in Remote Sharing: the version in use, Check Now, Update to the latest release (downloaded into Application Support), Use Built-In. |
| `AboutView.swift` | About panel (icon, version, fainimade.com, software policy, privacy policy, bundled versions, Capture One disclaimer) and the Acknowledgments window with cloudflared's and Python's licences, which they require to ship with the app. |
| `UpdateChecker.swift` | "Check for Updates…" in About (copied from PortScope): asks GitHub for the latest release of `titleunknown/LfS-Viewer`; optional daily check, off by default. |
| `ViewersSection.swift` | The Viewers panel: each connected browser (device type; This Mac / network IP / remote with Cloudflare Access email, IP linked to ipinfo.io, and location from Cloudflare's headers linked to Apple Maps; folder and photo; connected for; ratings and tags set; rating rights; data sent), Remove (blocks the device until Unblock) and Stop Rating on one device; then "Recently left" (the last hour); then Removed. Fed by the viewer's `devices` events. |
| `RemoteSection.swift` | The Remote Sharing panel: switch, your domain or temporary link, token, public address, viewing code, setup steps. |

Settings that belong to the viewer (rating mode, PIN, wrong-PIN limits, remote code) live in the
viewer's own `settings.json` in `~/Library/Application Support/LfS Viewer/`, changed only through
commands. They are separate from the `settings.json` next to the script in the main folder, which
the double-click launcher still uses. App preferences (port, startup, Dock) are in UserDefaults.

## Remote sharing

People outside the studio can watch through Cloudflare, with the viewing code. Two ways:

- **Your domain:** a Cloudflare Tunnel you make once in the dashboard (Networking › Tunnels;
  older dashboards: Zero Trust › Networks › Tunnels), with a published application (route) such as `studio.yourdomain.com` whose Service
  URL is `http://localhost:8797` (with `http://`: the dashboard requires the protocol). Paste the tunnel's token (or the whole install command, which the app
  picks the token out of) and the public address into the window. The window has the steps.
- **Temporary link:** a random `https://….trycloudflare.com` address, new each time. No account.

For users, all of this is explained step by step in `remote-setup.html` (in the main folder, bundled in
the app and opened by **Setup Guide…** with the tunnel port filled in): creating a Cloudflare account,
moving or buying a domain, the tunnel, the route, testing, keeping it running and troubleshooting.
Its dashboard paths were checked against Cloudflare's docs and a real setup on 2026-10-20; if
Cloudflare renames menus, update both the guide and the steps in `RemoteSection.swift`.

How it works:

- Switching sharing on asks the viewer to open its tunnel port (`{"cmd": "tunnel"}`, live, so
  viewers on the network stay connected), then runs the bundled `cloudflared`. Switching off, or
  the viewer stopping, stops cloudflared and closes the port. Sharing stays switched on across
  launches and resumes with the viewer.
- The tunnel port is 8797 by default (Settings), outside the 8787-8796 range the viewer's main
  port may move to. It only listens on 127.0.0.1.
- cloudflared runs isolated from anything else on the Mac (such as PIX's `~/.cloudflared`): its own
  `HOME` and its own config (`~/Library/Application Support/LfS Viewer/cloudflared/`).
- The token is in the login Keychain (item "LfS Viewer: Cloudflare tunnel token") and is handed to
  cloudflared in its environment, never on its command line. It's read only when sharing starts,
  off the main thread, so a Keychain prompt never holds up the app. Preferences keep only the
  tunnel's ID, to show that a token is saved.
- Status comes from cloudflared's metrics server (`/ready` for the connection count, `/quicktunnel`
  for a temporary link's address). Notifications after 15 s without a connection, and when it's
  back. cloudflared retries forever on its own, a wrong token included, so the app gives up after
  30 s without a first connection and says why ("Cloudflare doesn't recognise this tunnel…").
- Remote visitors always need the viewing code unless "Ask for a viewing code" is turned off,
  which the app only allows after a warning, for addresses protected by Cloudflare Access.
- If the app crashes, a cloudflared it left running is stopped at the next launch.

`App/scripts/fetch-cloudflared.sh` downloads cloudflared for Apple Silicon (Apache-2.0; the licence
is bundled next to it) into `App/Cloudflared/`, checks the program's SHA-256 against the release
notes (they list the program's checksum, not the `.tgz`'s) and that it's signed by Cloudflare Inc.
(team 68WVV388M8). The bundled version is 2026.10.2 (`TAG=2026.10.2` fetches it again). The build
phase ("Bundle helpers", `scripts/bundle-helpers.sh`) signs and caches it like Python.

Between app releases, the Remote Sharing panel shows the cloudflared version in use and offers
**Update to …** when GitHub has a newer release (checked when the panel opens, at most hourly, or
with **Check Now**). The update never touches the app: it goes into
`~/Library/Application Support/LfS Viewer/cloudflared/bin/cloudflared` after the same checks as the
fetch script (release-notes SHA-256 of the program, Cloudflare's Developer ID signature, and that it
runs). At launch the app runs whichever copy is newer, a downloaded one only while its signature
still checks out, so a later app release with a newer bundled copy takes over again (and the
download, never needed again, is deleted). The choice is made off the main thread; sharing waits
for it before starting. Updating while
sharing restarts cloudflared on the new version, keeping the viewer's tunnel port open, so remote
visitors only wait for the reconnect. **Use Built-In** deletes the download and goes back. Tested
2026-10-26 on the own-domain tunnel: 2026.10.2 → 2026.10.4, reconnected with the gate and a 401 from
outside; Use Built-In and back; a relaunch picked the downloaded copy. Then, with 2026.10.4 bundled
too, a relaunch deleted the download and shared on the built-in copy.

Tested 2026-10-20 against a fake Capture One (no real photos online), over the real internet:
temporary link connected; without the code the page asks for it and the API answers 401; a wrong
code is refused; the right code sets a `Secure` cookie (the viewer saw HTTPS through Cloudflare);
the visitor is never the owner; the app counted "1 watching remotely"; switching off stopped
cloudflared, closed the port (the link then gave Cloudflare's 530) and left network viewers
connected; quitting the app stopped cloudflared; sharing resumed by itself after relaunch.
Not tested in the app: a real own-domain tunnel (needs your Cloudflare account), and the 30 s
give-up with a wrong token (cloudflared's behaviour with one was checked on its own).

Hidden setting for troubleshooting and tests:
`defaults write Faini-Made.LfS-Viewer captureOneAddress 127.0.0.1:PORT` makes the viewer use that
Capture One address (`--c1`); `defaults delete Faini-Made.LfS-Viewer captureOneAddress` undoes it.

## Icon

An eye whose iris is a camera aperture, in the viewer's amber, on its dark charcoal, inside
viewfinder corner marks with a green "live" dot. It is drawn in code
(`App/Icon/LfSIcon.swift`, SwiftUI, Apple's 824-on-1024 icon grid), like PortScope's icons. After
changing it:

```sh
App/Icon/make-iconset.sh   # renders icon-1024.png and fills every AppIcon size
```

## Python

`App/scripts/fetch-python.sh` downloads a self-contained Python 3.13 for Apple Silicon
(python-build-standalone), checks its SHA-256, and trims it into `App/Python/` (48 MB unpacked;
`App/Python/VERSION` names the build). The bundled one is currently
`cpython-3.13.16+20261020`. To fetch exactly that again, or update to a newer release:

```sh
TAG=20261020 App/scripts/fetch-python.sh   # a specific release
App/scripts/fetch-python.sh                # the latest release
```

The "Bundle helpers" build phase (`scripts/bundle-helpers.sh`) copies it into the app and signs
every binary in it with the app's identity. The signed copy is cached and only redone when the
Python version, identity or configuration changes, so incremental builds keep the app's
signature valid (`codesign --verify --deep --strict` passes after clean, incremental and
Python-update builds). Without `App/Python/`, the build says so and the app uses this Mac's own
`python3` (Homebrew, or the Command Line Tools'). Settings › Files shows which one is in use.

It is Apple Silicon only. Intel Macs would need the x86_64 build merged in with `lipo`.

## Releasing

```sh
App/scripts/release.sh
```

It archives a Release build, signs it with the team's **cloud-managed Developer ID** certificate
(there's no Developer ID certificate in the keychain; Xcode fetches signing from the Apple account
in Xcode › Settings › Accounts), uploads it to Apple's notary service, waits, and exports the
stapled app plus `LfS-Viewer-<version>.zip` into `App/build/release/`. No passwords or API keys
are involved. Bump `MARKETING_VERSION` in the target's build settings first.

What the first run (version 0.1, 2026-10-20) showed:

- Xcode's export re-signs the bundled Python's binaries in `Contents/Resources/python` with
  Developer ID too. All 8 Mach-O files had Developer ID, hardened runtime and a secure timestamp.
- Apple notarized it in about a minute; `stapler validate` passed.
- Gatekeeper accepted it (`source=Notarized Developer ID`), including a copy marked as downloaded
  by Safari, and `syspolicy_check distribution` said it "passed all pre-distribution checks".
- The notarized app ran its bundled Python under the hardened runtime with no extra entitlements,
  and served the live session, photos and exposure info.
- The zip is 20 MB.

### Publishing a release (for Check for Updates)

The About panel's **Check for Updates…** reads the latest release of the GitHub repo
`titleunknown/LfS-Viewer` (`UpdateChecker.repo`; change it there if the repo gets another name). Until
that repo exists and is public, the button just says it couldn't check. For each release:

1. Bump `MARKETING_VERSION` (for example 0.2) and run `App/scripts/release.sh`.
2. On GitHub, create a release tagged `v0.2` (or `0.2`) and attach `LfS-Viewer-0.2.zip` from
   `App/build/release/`. Tags with `-beta` count as their base version, so `v0.3-beta.1` never
   reads as newer than 0.3.
3. Anyone who presses **Check for Updates…**, or has the daily check on, is offered **Download…**,
   which opens the repo's releases page.

Updates always replace the whole app. The bundled Python and cloudflared are never updated on
their own (that would break the app's signature and notarization): refresh them with the fetch
scripts and ship a release. (cloudflared can also be updated from the Remote Sharing panel, but
that copy lives outside the app, in Application Support.) Do this for cloudflared every few months, since Cloudflare stops
supporting old versions after about a year.

Not exercised: the "downloaded from the Internet, open?" prompt a person sees on first open,
because that needs a click on a system security dialog.

## Not done yet

- **Notarizing with cloudflared:** v0.1 was notarized before cloudflared was bundled. It should
  pass the same way as Python (Xcode's export re-signs it), but run `release.sh` to confirm.
- **Hidden menu bar icon:** on a crowded menu bar (the notch, or a menu bar manager), macOS may
  hide the icon. The window and Settings still work; ⌘-drag icons to make room.
