<div align="center">

![Codenotch](docs/design/codenotch-banner.png)

[![CI](https://github.com/vinzdg/codenotch/actions/workflows/ci.yml/badge.svg)](https://github.com/vinzdg/codenotch/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Swift](https://img.shields.io/badge/swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**A macOS system activity monitor app that pins a small black notch to a screen edge, showing real-time System RAM, CPU Load, Thermal Pressure, Network Speed, and Energy/Battery usage.**

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

</div>

Hover a ring for detailed breakdown of system memory, CPU load across user and system processes, thermal state, upload/download network throughput, and power source/battery status.

## Download

[![Download for macOS](docs/design/download-macos.svg)](../../releases/latest/download/Codenotch.dmg)

That button is the disk image itself, not the page it sits on — the asset is
named `Codenotch.dmg` in every release, so `releases/latest/download/` always
resolves to the newest one and the link never needs updating. Signed,
notarized, and updating itself from then on. Take this one unless you have a
reason not to; the [release page](../../releases/latest) has the notes.

To try unreleased `main` without an Xcode install, the [preview
build](../../releases/tag/preview) is rebuilt from every commit, and the
Package workflow keeps a per-commit disk image on each of its
[runs](../../actions/workflows/package.yml). Neither is notarized — they are
ad-hoc signed, because the Developer ID certificate exists on one machine — so
macOS quarantines the download. Clear the flag once, after dragging the app to
Applications:

```sh
xattr -dr com.apple.quarantine /Applications/Codenotch.app
```

If macOS says the app is *damaged*, that is the quarantine flag rather than a bad download — run the command above.

Universal binary. macOS 15 or later. To build and install a copy from source
instead, see [Building](#building).

## Windows

[![Download for Windows](docs/design/download-windows.svg)](../../releases/latest/download/Codenotch-Setup.exe)

A Windows port — Rust/Tauri 2, same design and providers — lives in [`windows/`](windows/README.md).
The button is the installer itself, named `Codenotch-Setup.exe` in every release for the same
reason the dmg keeps one name. It installs for the current user without administrator rights,
and fetches WebView2 if Windows does not already have it.

The installer is not code-signed, so the first time it runs SmartScreen says *Windows protected
your PC*. Choose **More info**, then **Run anyway**. Every Windows change also leaves an
installer on its [Windows Package run](../../actions/workflows/windows-package.yml).

## Connect your phone

The Codenotch phone app (iOS and Android) can show the same usage
percentages, reset times and session states as the notch on your Mac.
It reads only what the notch already displays — never tokens, credentials
or raw API responses.

To pair, open **Settings › Phone › Connect a Phone…** (or the menu item)
on your Mac. A QR code appears with a five-minute countdown; scan it with
the Codenotch phone app, or copy the link and paste it into the app. The
Mac and phone must be on the same Wi-Fi network — the server answers only
local-network addresses and rejects anything routed over the internet.

Each code is single-use and expires after five minutes. Reopening the
window always mints a fresh one.

To remove a paired phone, open **Settings › Phone**, find the device in
the list and click **Remove**. Its credentials are deleted immediately and
any subsequent request from that phone is rejected.

See [docs/phone-link-protocol.md](docs/phone-link-protocol.md) for the
wire-level details.

## What it reads

| Metric | Source | Details |
|---|---|---|
| **RAM** | macOS System API | Real-time memory usage (Used, App Memory, Wired Memory, Compressed). |
| **CPU** | macOS System API | Overall CPU load % split into User and System processes across active cores. |
| **Thermals** | macOS System API | System thermal state and pressure level (Nominal, Fair, Serious, Critical). |
| **Network** | macOS System API | Real-time download and upload throughput speeds (KB/s, MB/s). |
| **Energy** | macOS System API | Battery level, power source (AC / Battery), and charging status. |

Settings lists the connected system metrics in the order the notch draws them, and
you can drag any metric by its handle to reorder them. The order is remembered across
launches.

The notch opens itself for five seconds when an agent stops working, or stops
to ask you something, and sounds the system alert. Clicking it while it is open
brings that session's application to the front.

The app, not the tab. A session publishes its pid and nothing else — no window,
no tab, no tty — so the app is found by walking up the process tree from the
agent to whatever launched it. Choosing the *tab* inside that app needs the
terminal's own scripting interface, and there is no general one: Terminal.app
and iTerm2 can match a tab by tty, Warp and Ghostty publish no scripting
dictionary at all. So the app is raised for everybody and the tooltip names the
session, which leaves the last hop one keystroke rather than working for two
terminals and silently doing nothing in a third.

Both halves switch off separately in Settings, because they fail differently:
the peek is no use behind a full-screen window, and the sound is no use in a
meeting. Each of the two events — finished, and waiting on you — picks its own
sound there, with a preview button beside it.

The sound is played as a file on the ordinary output rather than handed to
`NSSound` as a system alert. A system alert goes through the interface
sound-effects channel, which System Settings → Sound can switch off — and on a
Mac where it is off, `NSSound.play()` reports success and nothing is heard.

Only *leaving* busy counts. A question being answered is not a piece of work
ending, and a session whose file disappears mid-turn — which is what quitting
Claude Code looks like — is not announced at all, since there is no window left
to jump to. Nothing is announced from the first reading either: every session
already running at launch arrives with no history, and treating that as a
transition would ring once per open window on every start.

## Alerts

A provider's headline limit crossing **80%** — and reaching **100%** —
becomes a system notification: once per crossing, never repeated while it
stays crossed, and again only after the window has genuinely rolled over.
Each provider can be muted from its own row in Settings, and macOS permission
is asked on the first real alert rather than at launch.

## Placement

The notch lives on any of the four screen edges. Right and left keep a
vertical column; top and bottom lay the readings out side by side. It pins
itself to the physical screen edge, so showing or hiding the Dock does not
move it. Hold Option and drag to move along the selected edge; each edge
remembers its position. On a Mac with a hardware notch, the top
placement takes its exact shape, so the two read as one rather than as a bar
parked underneath it.

Along that edge it sits wherever you put it: hold ⌥ and drag the notch to
slide it, and each edge remembers where you left it, so moving the notch to the
top and back does not lose the place you chose on the right. **Recentre** in
Settings → Appearance puts the current edge back in the middle.

**Size** in the same place draws the whole notch — rings, text, tooltip and all
— smaller or larger. Medium is the size it was designed at.

At rest it is a small pill on the screen edge that unfolds when the pointer
reaches it — configurable in Settings to always show, or to hide entirely.
Settings live in an orb below the notch: an arc at rest, a gear on hover.

Clicking the notch while it is open keeps it open, so it stays put while you
read it; clicking it again lets it fold away as usual. That click has to land
on the body itself, since a ring takes its own click to refetch that provider
and the orb takes one to open Settings. Right-clicking offers the same thing as
a menu item, **Keep open**, ticked while the notch is being held open, which is
the surer way to release one that was kept open by accident. The item is
greyed out when Settings says Always show, because that choice is Settings' to
change.

In Settings → Appearance → Reset time, choose **Time remaining** for countdowns
like "Resets in 3 Days 3h". **Reset date** keeps the reset date and time, with
minutes shown when less than an hour remains.

Appearance also carries the ring's accent colour. The device accent is the
default; fixed presets are available for pink, red, orange, yellow, green,
teal, blue, indigo, purple and off-white.

The app itself can show a Dock icon, a menu bar item, or neither. The menu bar
item is the Codenotch icon until you switch on **Show limit information in
menu bar** under Settings → Appearance → App; then it shows the five-hour
limits of the providers you choose there — the provider's mark, the share used
and the time until it resets, like `72% · 2h 18m | 41% · 4h 05m`. Choosing
what the bar shows never changes what Codenotch reads, and with nothing chosen
the icon comes back. Its menu has the full readings either way.

## Updates

Codenotch updates itself. [Sparkle](https://sparkle-project.org) checks daily
and installs in the background without prompting; Settings says so and can
switch it off. Every update is EdDSA-signed, so nothing installs that wasn't
built and signed by the maintainer.

## Building

```sh
brew install xcodegen create-dmg   # once
make run                # generate, build, launch a Debug build
make test               # unit tests
```

No signing identity is required for either. `make release` — which archives,
notarizes, and produces a signed auto-update feed — needs a Developer ID
certificate and an App Store Connect notary profile, and is only ever run by
the maintainer to cut an official release. See
[CONTRIBUTING.md](CONTRIBUTING.md). CI runs the same unit tests unsigned via
`make test-ci`.

A Debug build is ad-hoc signed, which means it has no stable code identity, so
macOS cannot match it to a saved keychain "Always Allow" — the prompt to read a
tool's token returns on every launch. To make the grant stick during local
development, sign the built app with a stable self-signed identity:

```sh
Scripts/sign-local.sh   # signs /Applications/Codenotch.app (pass a path to override)
```

It creates a reusable `Codenotch Local Signing` certificate in your login
keychain (no Apple Developer account needed) and re-signs the app. Grant the
keychain prompt once more after signing; it will not ask again.

Run with `CODENOTCH_DEMO=1` to see fixed sample data instead of live readings.

## Architecture

Every provider implements `UsageProvider` (`Sources/Providers/`) and declares
its own `Fidelity` — `.official`, `.derived`, or `.manual` — so the UI never
presents a guess as if a vendor had published it. `UsageStore`
(`Sources/Model/`) polls them on a timer, keeps the last good reading across
launches, and degrades every failure to a visible status rather than a
made-up percentage.

The notch itself works in one-dimensional **stack space** (`along`/`across`)
regardless of which screen edge it's on; `NotchPlacement` is the only place
that maps that back onto real screen coordinates. `NotchLayout` holds every
measurement, quoted from `docs/design/frame-124-hover-tooltip.png` so the
layout can be checked against the design frame directly.

- Design spec: [`docs/specs/2026-08-28-usage-notch-design.md`](docs/specs/2026-08-28-usage-notch-design.md)
- Implementation history: [`TASKS.md`](TASKS.md)

## Logging

The app logs diagnostics to the unified log:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Vinz
