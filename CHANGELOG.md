# Changelog

All notable changes to Zest. Versions before v3.0 were not tracked in this file.

## v3.0

- Signed and notarized Developer ID release: download from Releases, no Xcode required.
- Privileged helper (`zest-smc`) for Low Power Mode toggle and true per-app powermetrics energy.
- Ecosystem battery view, health history with capacity trendline, energy grading, Ubersicht panel embedding, local LM Studio digest.

## Unreleased

- README: merged the two conflicting Install sections; the notarized download is primary, build-from-source is the alternative.
- build.sh: no personal signing identity as default; `ZEST_SIGN_IDENTITY` is required for Developer ID signing.
