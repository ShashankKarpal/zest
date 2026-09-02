# Changelog

All notable changes to Zest. Versions before v3.0 were not tracked in this file.

## v3.0

- Signed and notarized Developer ID release: download from Releases, no Xcode required.
- Privileged helper (`zest-smc`) for Low Power Mode toggle and true per-app powermetrics energy.
- Ecosystem battery view, health history with capacity trendline, energy grading, Ubersicht panel embedding, local LM Studio digest.

## Unreleased

- README: merged the two conflicting Install sections; the notarized download is primary, build-from-source is the alternative.
- build.sh: no personal signing identity as default; `ZEST_SIGN_IDENTITY` is required for Developer ID signing (the default was still present until 2026-09-02; now actually removed).
- Security (2026-09-02 fleet audit): the sudoers grant for `powermetrics` is pinned to the exact argument vector Zest runs instead of allowing any arguments (an unrestricted grant let any user process create or truncate arbitrary files as root via `-o`). `install-helper.sh` refuses to install when `/usr/local` or `/usr/local/libexec` is not root-owned (sudoers path-hijack). `trigger-install.sh` logs to a `mktemp` path.
- New `zest-smc/uninstall-helper.sh` and `scripts/uninstall-launchagent.sh`; README gained an Uninstall section and an accurate description of the helper (the app never prompted for a password; the README said it did).
- `install-launchagent.sh` resolves the app path from the repo location (or `ZEST_APP`) instead of a hard-coded `~/Projects/zest`.
- Config is written atomically, and an undecodable `config.json` is preserved as `config.json.bad` instead of being overwritten with defaults.
- `exportJSON` no longer silently writes nothing when a health value is missing (optionals are encoded as null).
- The Accessibility notification dismisser matches exact macOS battery phrases only; it used to close any banner containing "charge".
- BLE cache path fixed (`~/../tmp` had resolved to `/Users/tmp`); the reader now trusts only a regular file owned by the current user.
