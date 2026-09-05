# Changelog

All notable changes to Zest. Versions before v3.0 were not tracked in this file.

## v3.0

- Signed and notarized Developer ID release: download from Releases, no Xcode required.
- Privileged helper (`zest-smc`) for Low Power Mode toggle and true per-app powermetrics energy.
- Ecosystem battery view, health history with capacity trendline, energy grading, Ubersicht panel embedding, local LM Studio digest.

## Unreleased

- Energy pass (2026-09-02 audit Z-B1, Z-B2, Z-B4, Z-B7, Z-B8). Panel scripts now run only while something shows their output (the Command Center window, or the menu bar readout for the account panels) and never overlap themselves; before, all four ran from launch forever, and a 5 s System Vitals script that took longer than 5 s ran 98 percent of the time. `system_profiler SPPowerDataType` moved off the main thread (it used to block the UI for 2 to 12 s inside every hourly refresh); cycle count is read from the IORegistry on every refresh. One shared `system_profiler SPBluetoothDataType` snapshot per 30 s serves both the Devices list and Presence instead of two runs. Low Power Mode state comes from `ProcessInfo` (no shell; the old `pmset -g | grep` ran on the main thread inside a SwiftUI body on every redraw, and on current macOS always read Off). The helper probe at launch runs off the main thread. `EnergySampler` runs on one serial queue and skips a tick instead of overlapping a slow powermetrics run; it also stops rewriting the multi-megabyte energy history on every 12 s tick (now every 5 minutes plus on quit) and stops allocating a DateFormatter per bucket per pass, which turned out to be most of Zest's own idle CPU. `Shell.run` waits on the child instead of polling every 20 ms. Measured on the running app over two 600 s windows: Zest CPU time 25.9 s before, 1.9 s after (about 4.3 percent of a core down to 0.3), panel-script spawns 14,235 sample hits before, 0 after, Bluetooth profiler runs roughly halved.
- First unit tests: `swift test` runs 25 XCTest cases over config decoding (tolerant decode, panel gate default off, round trip), panel gating (inert runner, missing script never spawns, four personal sections), battery snapshot math, health projection, and the JDict accessor. `BatteryHistory.projection` became a pure static function so it can be tested without touching disk. New `build` GitHub Actions workflow runs the tests and a release `build.sh` on a macOS runner, so a broken build no longer waits for someone's local build to notice.
- Widget panels are gated behind a `panelsRoot` setting (Settings > General > Widget panels). With no folder chosen, which is every fresh install, the four personal Command Center sections (Account 1, Account 2, System Vitals, Claude Code) are hidden, no panel script is ever spawned, and the menu bar readout picker that depends on them is hidden. Before this, the public build showed the sections empty and ran `/bin/bash` against hard-coded `~/Projects/zest/panels/*.sh` paths every 5 to 30 seconds (2026-09-02 audit Z-B3, Z-A8). The runner also stays silent when a chosen folder goes missing instead of failing four times a cycle.
- The privileged helper is looked up only at its installed path `/usr/local/libexec/zest/zest-smc`; the old `~/Projects/zest/zest-smc/zest-smc` fallback could never have passed the sudoers grant.
- In-app privacy text no longer describes a VPN egress check that belongs to one user's own panel script.
- README: merged the two conflicting Install sections; the notarized download is primary, build-from-source is the alternative.
- build.sh: no personal signing identity as default; `ZEST_SIGN_IDENTITY` is required for Developer ID signing (the default was still present until 2026-09-02; now actually removed).
- Security (2026-09-02 fleet audit): the sudoers grant for `powermetrics` is pinned to the exact argument vector Zest runs instead of allowing any arguments (an unrestricted grant let any user process create or truncate arbitrary files as root via `-o`). `install-helper.sh` refuses to install when `/usr/local` or `/usr/local/libexec` is not root-owned (sudoers path-hijack). `trigger-install.sh` logs to a `mktemp` path.
- New `zest-smc/uninstall-helper.sh` and `scripts/uninstall-launchagent.sh`; README gained an Uninstall section and an accurate description of the helper (the app never prompted for a password; the README said it did).
- `install-launchagent.sh` resolves the app path from the repo location (or `ZEST_APP`) instead of a hard-coded `~/Projects/zest`.
- Config is written atomically, and an undecodable `config.json` is preserved as `config.json.bad` instead of being overwritten with defaults.
- `exportJSON` no longer silently writes nothing when a health value is missing (optionals are encoded as null).
- The Accessibility notification dismisser matches exact macOS battery phrases only; it used to close any banner containing "charge".
- BLE cache path fixed (`~/../tmp` had resolved to `/Users/tmp`); the reader now trusts only a regular file owned by the current user.
