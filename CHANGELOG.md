# Changelog

All notable changes to Zest. Versions before v3.0 were not tracked in this file.

## v3.0

- Signed and notarized Developer ID release: download from Releases, no Xcode required.
- Privileged helper (`zest-smc`) for Low Power Mode toggle and true per-app powermetrics energy.
- Ecosystem battery view, health history with capacity trendline, energy grading, Ubersicht panel embedding, local LM Studio digest.

## Unreleased

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
