# CLAUDE.md

## Security and hygiene rules (every agent session)

1. Never commit secrets: no API keys, tokens, passwords, private keys, or .env files. Templates belong in *.example files with placeholder values only.
2. Untracking or deleting a file does not remove it from git history. If a secret ever lands in a commit: rotate it at the provider first, then rewrite history with git filter-repo.
3. At the end of each session: delete unused code, merge duplicate helpers, remove commented-out blocks. Use deterministic tools (linters, dead-code finders) and review the diff before deleting.
4. Keep .gitignore covering .env, .env.*, and secrets.* (with !*.example exemptions). Never weaken it.
5. The gitleaks CI workflow (.github/workflows/gitleaks.yml) stays. Never remove or bypass it.

## 2026-09-02: fleet audit pass (kk1), helper hardening and release hygiene
- Sudoers: the powermetrics grant is now pinned to the exact argv the app runs; install-helper.sh refuses to install under a non-root-owned /usr/local. The owner re-ran `sudo bash zest-smc/install-helper.sh` on 2026-09-02 20:44 (`/etc/sudoers.d/zest-smc` root:wheel 0440, content verified pinned on 2026-09-03), so the live grant matches the shipped installer.
- Uninstall scripts added for the helper and the LaunchAgent; README gained an Uninstall section and no longer claims a first-launch password prompt that the app never had.
- Atomic config writes, undecodable config preserved as .bad, exportJSON null handling, notification dismisser narrowed to exact macOS phrases, BLE cache path corrected with an owner check, mktemp for the installer and notarize logs, build.sh default identity actually removed.
- QUIRK (found today): after rebuilding Zest.app in place, `launchctl kickstart -k gui/501/com.zest.app` fails with `last exit reason = OS_REASON_CODESIGNING` and the kernel logs an AMFI Launch Constraint Violation, even though the new build verifies and launches fine by hand. launchd pins the program's code identity at bootstrap. Fix: `launchctl bootout gui/501/com.zest.app` then `launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.zest.app.plist`. Build with `ZEST_SIGN_IDENTITY='Developer ID Application: ...'` so the running copy keeps the hardened-runtime signature the deployed app had.
- Deferred to the fleet roadmap: gating the personal Claude/TokenEater panels out of the public build, system_profiler and Bluetooth scan dedupe, Low Power state cache, Homebrew cask (retag v3.0), ecosystem push, menu bar deck row, helios feed, 30-second tour GIF.

## 2026-09-05: panel gating (kk2)
- Personal panels are behind `panelsRoot` in config.json (nil by default). `~/Projects/zest` has not existed since the 2026-07-30 consolidation, so the four panels had been dead on this Mac too, with bash spawned against a missing script every 5 to 30 s. The owner's config now points at `~/Projects-with-Claude/zest/panels`; a fresh install shows six sections and spawns nothing.
- Build and relaunch rule unchanged: `bash build.sh` with `ZEST_SIGN_IDENTITY` set, then `launchctl bootout gui/501/com.zest.app` and `launchctl bootstrap gui/501 ~/Library/LaunchAgents/com.zest.app.plist`. Never `kickstart -k` after an in-place rebuild.
- Ranked next-5 with red team: `_inbox/app-fleet-roadmap/next5/zest-2026-09-05.md`.
