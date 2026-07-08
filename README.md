# QuotaPace

A macOS menu bar tracker for your AI quotas (GitHub Copilot premium requests and, optionally, Google Antigravity model quotas), built as a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin.

Shows your Copilot usage percentage in the menu bar. The dropdown shows one usage bar per quota with a pace tick marking how much of the quota window has elapsed, reset dates, and a header status naming any quota that's burning faster than time passes.

## Prerequisites

- macOS
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`)
- [GitHub CLI](https://cli.github.com/) (`gh`), already authenticated (`gh auth login`) with access to a GitHub Copilot seat
- `jq` (`brew install jq`)

## Install

```bash
git clone <this-repo> quotapace
cd quotapace
./install.sh
```

Then open SwiftBar, go to **Preferences > Plugins**, and set the Plugin Folder to `~/.swiftbar-plugins` (or wherever `install.sh` printed).

## Repository layout

```
quotapace.5m.sh              the plugin, everything in one file by design
helpers/quotapace-login.sh   "Sign in with GitHub…" recovery action
install.sh                   copies both files into place
.github/workflows/ci.yml     shellcheck + syntax check on every push
```

SwiftBar executes a single file per plugin from its plugin folder, so `quotapace.5m.sh` deliberately stays one self-contained script: no sourced libraries, no build step.

SwiftBar also treats every executable file placed in its plugin folder as its own plugin and runs it automatically. `quotapace-login.sh` (used for the "Sign in with GitHub…" recovery action if `gh` isn't authenticated) must **not** live in the plugin folder, or SwiftBar will silently execute `gh auth login --web` on every launch. `install.sh` handles this by installing it to `~/.quotapace-helpers/` instead.

## How it works

QuotaPace shells out to `gh api /copilot_internal/user`, an internal (undocumented) endpoint that GitHub's own Copilot clients use to check quota. It refreshes every 5 minutes (encoded in the `quotapace.5m.sh` filename, per SwiftBar's plugin naming convention).

Since this endpoint only reports a live snapshot (not historical usage), the "expected pace" comparison is computed locally by assuming a monthly billing cycle ending on `quota_reset_date`.

The last successful response is cached at `~/Library/Caches/quotapace/quota.json`. When GitHub is unreachable (offline, DNS trouble, outage), the menu renders from that cache with an "Offline · cached data from …" note and a wifi-slash icon instead of an error, and it only asks you to sign in again when GitHub actually rejects the token (HTTP 401).

## Antigravity (optional)

If the [antigravity-usage](https://github.com/skainguyen1412/antigravity-usage) CLI is installed (`npm install -g antigravity-usage`, then a one-time `antigravity-usage login`), the dropdown gains an Antigravity section with one bar per quota group: all Gemini models share one weekly quota, all Claude/GPT models another. The pace tick marks how much of the 7-day window has elapsed. The header status and menu bar color reflect the worst pace across all quotas, naming the offending quota (e.g. "Antigravity Gemini over pace"). The last good response is cached at `~/Library/Caches/quotapace/antigravity.json` and shown with a "cached from …" note when the CLI fails; without the CLI the section simply doesn't appear.

## Caveats

- `/copilot_internal/user` is not a public documented API and could change without notice.
- The pace calculation assumes a monthly reset cycle starting one calendar month before the reported reset date, which is accurate for standard GitHub Copilot business/enterprise billing but may not match unusual cycles.

## License

[MIT](LICENSE)
