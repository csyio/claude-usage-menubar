# claude-usage-menubar

A macOS menu bar app that shows your Claude plan limits and Claude Code token usage.

The menu bar shows the 5-hour window utilization and time until reset, e.g. `42% · 2sa 13dk`.
Clicking it opens a panel with:

- 5-hour and weekly limit utilization with reset times
- Claude Code usage for today, the last 5 hours, or the last 7 days
- Breakdown by model and by project, in tokens and API-equivalent cost

The UI is in Turkish.

## Requirements

- macOS 14 or later
- Swift 5.10+ (Xcode or Command Line Tools)
- Claude Code installed and logged in with a Claude subscription (Pro or Max)

## Install

```sh
git clone https://github.com/csyio/claude-usage-menubar.git
cd claude-usage-menubar
make install     # builds, copies to ~/Applications, and launches
```

Other targets: `make app` (build `build/Claude Kullanım.app` only), `make run`, `make clean`.

The app has no Dock icon. Enable "Girişte başlat" (launch at login) in the panel to start it automatically.

## How it works

**Plan limits** come from `https://api.anthropic.com/api/oauth/usage`, the same endpoint Claude Code
uses for `/usage`. The app reads Claude Code's OAuth access token from the macOS Keychain
(item `Claude Code-credentials`) through `/usr/bin/security` and sends it only to that endpoint.
It polls at most every 2 minutes. It never refreshes the token, because rotating the refresh token
would log Claude Code out. If the token has expired, open Claude Code once and it will refresh it.

These limits are shared across claude.ai, the desktop app, and Claude Code, so the percentages
include all of them.

**Token usage** is read from Claude Code's session logs in `~/.claude/projects/**/*.jsonl`
(subagent logs included). Files are read incrementally every 30 seconds. Claude Code writes one
line per content block, so entries are deduplicated by `message.id` + `requestId`. The project
name is taken from the log directory name (`-Users-you-Desktop-myapp` → `myapp`).
Usage in claude.ai chats is not stored locally and does not appear in these breakdowns.

**Cost** is calculated with Anthropic API list prices (`Sources/ClaudeUsage/Pricing.swift`),
including cache reads and 5-minute/1-hour cache writes. On a subscription you do not pay this
amount; it shows what the same usage would cost on the API.

## Limitations

- `/api/oauth/usage` is not a documented public API. If its response format changes, the panel
  shows an error and the token breakdowns keep working.
- Prices are hardcoded. Update `Pricing.swift` when they change.

## Debugging

```sh
.build/release/ClaudeUsage --dump
```

Prints today's usage per model and project, and the current plan limits, then exits.

## License

MIT
