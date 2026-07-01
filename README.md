# Octopace

A macOS menu bar tracker for your GitHub Copilot premium request quota and Codex rate limits, built as a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin.

Shows your remaining Copilot quota percentage and Codex 5-hour percentage in the menu bar. The dropdown shows clear text bars for Copilot premium requests, Codex's 5-hour limit, and Codex's weekly limit.

## Prerequisites

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`)
- [GitHub CLI](https://cli.github.com/) (`gh`), already authenticated (`gh auth login`) with access to a GitHub Copilot seat
- `jq` (`brew install jq`)

## Install

```bash
git clone <this-repo> octopace
cd octopace
./install.sh
```

Then open SwiftBar, go to **Preferences > Plugins**, and set the Plugin Folder to `~/.swiftbar-plugins` (or wherever `install.sh` printed).

## Why two files?

SwiftBar treats every executable file placed in its plugin folder as its own plugin and runs it automatically. `octopace-login.sh` (used for the "Sign in with GitHub…" recovery action if `gh` isn't authenticated) must **not** live in the plugin folder, or SwiftBar will silently execute `gh auth login --web` on every launch. `install.sh` handles this by installing it to `~/.octopace-helpers/` instead.

## How it works

Octopace shells out to `gh api /copilot_internal/user`, an internal (undocumented) endpoint that GitHub's own Copilot clients use to check quota. It refreshes every 5 minutes (encoded in the `octopace.5m.sh` filename, per SwiftBar's plugin naming convention).

Since this endpoint only reports a live snapshot (not historical usage), the "expected pace" comparison is computed locally by assuming a monthly billing cycle ending on `quota_reset_date`.

Codex limits are read from the latest local Codex session JSONL file containing a `rate_limits` snapshot.

## Caveats

- `/copilot_internal/user` is not a public documented API and could change without notice.
- The pace calculation assumes a monthly reset cycle starting one calendar month before the reported reset date, which is accurate for standard GitHub Copilot business/enterprise billing but may not match unusual cycles.
