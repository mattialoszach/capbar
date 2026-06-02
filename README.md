# CapBar

A compact macOS menu bar app for tracking AI coding-agent rate limits at a glance.

CapBar currently supports:

- Codex account login via `codex login`.
- Codex current-session and weekly limits via local `~/.codex/sessions` `rate_limits` metadata.
- Claude Code account login via `claude auth login`.
- Claude Code account status via `claude auth status --json`.
- Claude Code 5-hour and weekly limits via local Claude Code OAuth credentials and Anthropic's OAuth usage endpoint.

Claude Code usage is best-effort because Anthropic's local credential locations and OAuth usage endpoint are not public stable contracts. CapBar checks `~/.claude/.credentials.json` first, then the macOS Keychain item `Claude Code-credentials`, and never logs full tokens.

## Logos

Save transparent logo images here before building:

```text
Sources/CapBar/Resources/Logos/codex.png
Sources/CapBar/Resources/Logos/claude.png
```

If either image is missing, CapBar falls back to a neutral SF Symbol.

## Run

```sh
swift run CapBar
```

The menu bar label shows the selected provider icon, a compact white progress bar, and a small percentage. Click it to choose the provider, log in through the provider CLI, and view current-session plus weekly limit rows.

## Package as an App

```sh
chmod +x scripts/package_app.sh
scripts/package_app.sh
open dist/CapBar.app
```

The generated app is configured as a menu bar accessory app and will not show a Dock icon.
