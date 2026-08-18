<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)"  srcset="design/github/readme-banner-dark-1400x400.png">
    <source media="(prefers-color-scheme: light)" srcset="design/github/readme-banner-light-1400x400.png">
    <img alt="Zest" src="design/github/readme-banner-dark-1400x400.png" width="680">
  </picture>
</p>

<h1 align="center">Zest</h1>

<p align="center"><b>A native macOS menu bar battery command center. Power flow, health trends, ecosystem batteries, and alerts in one place.</b></p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-4D4323?style=flat-square">
  <img alt="Status" src="https://img.shields.io/badge/status-v3-4D4323?style=flat-square">
  <img alt="Local only" src="https://img.shields.io/badge/local-only-4D4323?style=flat-square">
  <img alt="Stack" src="https://img.shields.io/badge/built%20with-Swift-1A1917?style=flat-square">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-MIT-1A1917?style=flat-square"></a>
</p>

## What it does

- Replaces the built-in battery menu with a faster, richer one.
- Warns before you run low, and nudges at 80 percent.
- Names the apps draining the battery and grades them green, yellow, or red.
- Tracks battery aging with a capacity trendline and a months-to-80-percent projection.
- Shows every Apple device battery in one place.
- Embeds your own Ubersicht widgets as native panels.

## Features

### Menu bar and dropdown

- **iPhone-style battery pill** with the percent inside and a charging bolt on adapter.
- **Display options:** time remaining instead of percent, colors on or off, hide the number, dark glyph for light menu bars.
- **Optional panel readout** in the menu bar, pulled from one of your embedded panels.
- **Scrollable dropdown:** battery, charge state, power flow, health, devices, and the significant-energy list.

### Alerts

- **Unlimited custom alerts** at any percent, falling or rising.
- **Per-alert configuration:** glow, persistence, sound, on-screen position, color.
- **Notification pills** plus a screen-edge glow on the active screen.
- **Lifecycle alerts:** plugged in, unplugged, charged above 80 percent, fully charged.
- **Per-device low and full alerts.**
- **Quiet hours** with an option to still allow critical low-battery alerts.

### Battery health

- **Full health readout:** max capacity, cycle count, temperature, condition, voltage, design and full capacity.
- **Service recommendation** when capacity or condition warrants it.
- **Health history** with a capacity trendline, cycles per month, and a months-to-80-percent projection.

### Power flow

- **Live wattage diagram** from adapter to battery to Mac, animated.
- **Voltage and amperage** shown live.
- **Underpowered-adapter detection.**

### Energy insights

- **Per-app energy** via powermetrics, with a CPU-share fallback.
- **Live plus 24h, 7d, and 30d averages,** labeled by the real data span collected.
- **Using Significant Energy list** with real app icons.
- **Green, yellow, and red grading** per app and system-wide, with a threshold legend.
- **Misbehaving-app callout** when something runs well above its own baseline.

### Devices and ecosystem

- **Auxiliary device battery:** AirPods with left, right, and case, Magic accessories, and other Bluetooth gear.
- **Curated ecosystem view:** this Mac plus your iPhone, iPad, Watch, AirPods, and other Macs.
- **Presence when battery is unavailable.** iPhones and iPads do not report battery over Bluetooth, so Zest shows connected-via-Bluetooth or on-Wi-Fi presence and remembers it.
- **Scan Bluetooth** to add a paired device with its address filled in.
- **iPhone and iPad battery health** over a USB cable.

### Data and local AI

- **Exports:** battery health CSV, energy CSV, full JSON, and a weekly Markdown report.
- **Local battery digest** from your LM Studio model, fully on-device, with a graceful fallback when LM Studio is not running.
- **Late-night high-drain nudge.**

### Bring your own widgets

- **Ubersicht widget panels** rendered as native panels, each running its original pipeline verbatim.

### System

- **Menu bar only,** launch at login, single-instance lock, LaunchAgent for autostart and keep-alive.
- **Local only:** no accounts, no license check, no telemetry.

## Stack

- App: Swift, SwiftUI, AppKit
- Privileged helper: Swift, installed to a root-owned path
- Energy data: powermetrics
- Optional inference: LM Studio on localhost

## Install

**Requirements:** Apple Silicon, macOS 14 or later.

Download `Zest-v3.0-macOS.zip` from [Releases](https://github.com/ShashankKarpal/zest/releases/latest), unzip, and move `Zest.app` to `/Applications`.

Signed with an Apple Developer ID and notarized by Apple, so it opens without Gatekeeper warnings. No Xcode required.

**First launch:** Zest asks for your admin password once to install a privileged helper. This is required to read `powermetrics` for live power-flow data. That helper is also why Zest cannot ship on the Mac App Store: the sandbox forbids both root helpers and `powermetrics`, so a notarized direct download is the correct distribution channel.

**Verify it yourself:**

    ditto -x -k Zest-v3.0-macOS.zip .
    xcrun stapler validate Zest.app
    spctl -a -vvv Zest.app

Expect `source=Notarized Developer ID`.

### Build from source

Requires Xcode Command Line Tools.

```bash
git clone https://github.com/ShashankKarpal/zest.git
cd zest
./build.sh
open Zest.app
```

Unsigned builds are ad hoc signed and run fine on your own machine. To sign with your own Developer ID, set `ZEST_SIGN_IDENTITY` before building.

Autostart:

```bash
./scripts/install-launchagent.sh
```

## Configuration

Settings live in `~/Library/Application Support/Zest/config.json`, created on first launch and never committed. Energy history, health history, and exports live in the same folder.

Widget panel extraction reads its widget-to-script mapping from `panels/panels.local.json`, which is gitignored and machine-specific. Copy `panels/panels.example.json` to `panels/panels.local.json` and edit the widget paths to match your own Ubersicht setup.

## Permissions and flags

Each of these is off until granted, and each is a deliberate choice.

- **Low Power Mode toggle and true per-app powermetrics energy need root.** They run through the `zest-smc` helper, which is installed once to a root-owned path with a validated `sudoers` entry granting passwordless invocation of that helper and `powermetrics`. Until that entry exists, the app never calls it. Review `zest-smc/install-helper.sh` before running it.
- **Charge limit is deferred to the macOS 80 percent setting,** the safest option. Zest never writes charge state on this hardware.

## Project structure

```
Sources/Zest/       app: menu bar, alerts, battery, energy, devices, UI
zest-smc/           privileged helper and its installer
scripts/            LaunchAgent installer
panels/             widget extraction (generated pipelines are gitignored)
design/             brand assets, tokens, BRAND.md
docs/               screenshots
```

## Privacy

Everything is local. No accounts, no telemetry, no license server. The only network use is an optional VPN egress check and, if enabled, a request to LM Studio on localhost.

## License

MIT. See [LICENSE](LICENSE).

## Author

Built by Shashank Karpal.

> Designed and built with Claude (Anthropic).
