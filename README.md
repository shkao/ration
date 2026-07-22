<h1 align="center">Ration</h1>

<p align="center"><em>Your AI quota ration book, in the macOS menu bar.</em></p>

<p align="center">
  <a href="https://github.com/shkao/ration/actions/workflows/ci.yml"><img src="https://github.com/shkao/ration/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-macOS-lightgrey.svg" alt="Platform: macOS">
</p>

A macOS menu bar tracker for the AI quotas you didn't choose, built as a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin. It auto-detects which providers you use (GitHub Copilot premium requests via `gh`, Google Antigravity model quotas via the `antigravity-usage` CLI) and shows a section for each; with neither set up, the dropdown shows setup instructions instead.

The menu bar shows a gauge icon and your Copilot usage percentage, or the busiest Antigravity group when Copilot isn't detected; the gauge becomes a warning triangle when a ration is burning fast, so the worst state doesn't rely on color alone. The dropdown adds one usage bar per quota, reset dates, and a header line that names any off-pace quota. Hovering the menu bar item or a bar shows a tooltip explaining the numbers.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/ration-dark.png">
    <img src="assets/ration-light.png" alt="Ration's menu bar dropdown: a 26% gauge in the menu bar, with Copilot and Antigravity quota bars, reset dates, and an 'All rations on pace' status" width="340">
  </picture>
</p>

The `│` tick on each bar marks your fair share for right now: where usage would sit if you spread it evenly across the quota window. Fill past the tick means you're borrowing from tomorrow; the menu bar percentage turns orange, then red.

## Why "Ration"

A quota you set for yourself is a budget. A quota your company hands you is a **ration**: someone else decided how much you get, it never feels like quite enough, and your one job is to make it last until the next distribution day.

That's the exact situation this app models, and every part of the UI is ration-book arithmetic. The tick is today's fair share. Fill past the tick is bread eaten ahead of schedule. Reset day is distribution day. And when you hit 100%, the app stops pretending there's anything left to pace and says what everyone at the back of the queue already knows:

```
● Ration exhausted · see you on reset day
```

## Prerequisites

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`)
- `jq` (`brew install jq`)
- For Copilot: [GitHub CLI](https://cli.github.com/) (`gh`), signed in (`gh auth login`), with a Copilot seat
- For Antigravity: the `antigravity-usage` CLI (see below)

## Install

```bash
git clone https://github.com/shkao/ration.git
cd ration
./install.sh
```

Then open SwiftBar, go to **Preferences > Plugins**, and set the Plugin Folder to `~/.swiftbar-plugins` (or wherever `install.sh` printed). Upgrading from the QuotaPace days? `install.sh` removes the old plugin and helper so SwiftBar doesn't run both.

## Repository layout

```
ration.5m.sh              the plugin, everything in one file by design
helpers/ration-login.sh   "Sign in with GitHub…" recovery action
install.sh                copies both files into place
tests/run.sh              integration tests (stubbed gh, isolated $HOME)
.github/workflows/ci.yml  shellcheck on Linux, tests on macOS
```

SwiftBar executes a single file per plugin from its plugin folder, so `ration.5m.sh` deliberately stays one self-contained script: no sourced libraries, no build step.

SwiftBar also treats every executable file placed in its plugin folder as its own plugin and runs it automatically. `ration-login.sh` (used for the "Sign in with GitHub…" recovery action if `gh` isn't authenticated) must **not** live in the plugin folder, or SwiftBar will silently execute `gh auth login --web` on every launch. `install.sh` handles this by installing it to `~/.ration-helpers/` instead.

## How it works

Ration shells out to `gh api /copilot_internal/user`, an internal (undocumented) endpoint that GitHub's own Copilot clients use to check quota. It refreshes every 5 minutes (encoded in the `ration.5m.sh` filename, per SwiftBar's plugin naming convention).

Since this endpoint only reports a live snapshot (not historical usage), the "expected pace" comparison is computed locally by assuming a monthly billing cycle ending on `quota_reset_date`.

The last successful response is cached at `~/Library/Caches/ration/quota.json`. When GitHub is unreachable (offline, DNS trouble, outage), the menu renders from that cache with an "Offline · cached data from …" note and a wifi-slash icon instead of an error. Sign-in is only suggested when GitHub rejects the token (HTTP 401). Every fetch runs under a 15-second watchdog, so a stalled connection counts as a network failure and falls back to the cache instead of hanging the refresh.

## Antigravity

If the [antigravity-usage](https://github.com/skainguyen1412/antigravity-usage) CLI is installed (`npm install -g antigravity-usage`, then a one-time `antigravity-usage login`), the dropdown gains an Antigravity section with one bar per quota group: all Gemini models share one weekly quota, all Claude/GPT models another. Here the pace tick marks how much of the 7-day window has elapsed. The header status and menu bar color reflect the worst pace across all quotas and name the offender ("Antigravity Gemini over pace"). The last good response is cached at `~/Library/Caches/ration/antigravity.json` and shown with a "cached from …" note when the CLI fails. Without the CLI the section doesn't appear, and Antigravity works standalone: no `gh` needed if Copilot isn't your thing.

## Testing

```bash
./tests/run.sh
```

The suite runs the real plugin end to end against stub `gh` / `antigravity-usage` binaries and an isolated `$HOME`. It covers the happy path, pace escalation, the exhausted state, every error branch (offline, stalled network calls, expired token, no Copilot seat, missing dependencies), and both cache fallbacks. CI runs the suite on a macOS runner and shellcheck on Linux.

## Uninstall

```bash
rm ~/.swiftbar-plugins/ration.5m.sh
rm -rf ~/.ration-helpers ~/Library/Caches/ration
```

## Caveats

- `/copilot_internal/user` is not a public documented API and could change without notice.
- The pace calculation assumes a monthly reset cycle starting one calendar month before the reported reset date, which is accurate for standard GitHub Copilot business/enterprise billing but may not match unusual cycles.
- The Antigravity section shows percentages only: the `antigravity-usage` CLI doesn't expose absolute request counts.

## License

[MIT](LICENSE)
