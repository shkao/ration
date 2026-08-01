<h1 align="center">Ration</h1>

<p align="center"><em>Track your AI quota like a ration: know from your menu bar whether it'll last to reset day.</em></p>

<p align="center">
  <a href="https://github.com/shkao/ration/actions/workflows/ci.yml"><img src="https://github.com/shkao/ration/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-macOS-lightgrey.svg" alt="Platform: macOS">
</p>

Your employer hands you a fixed ration of AI requests: GitHub Copilot premium requests, Codex usage limits, Google Antigravity model quotas. Nothing warns you when you're spending it too fast, so you find out you've run out the hard way, when a request gets refused days before the reset. Ration keeps that number in your macOS menu bar and turns it orange, then red, the moment you're ahead of pace. It's a [SwiftBar](https://github.com/swiftbar/SwiftBar) plugin that installs in three commands and shows a section for each provider you use.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/ration-dark.png">
    <img src="assets/ration-light.png" alt="Ration's menu bar dropdown with Copilot, Codex, and Antigravity quota bars, reset times, and an overall pace status" width="330">
  </picture>
</p>

## What the menu bar tells you

The bar shows a gauge icon and one number: how much of your busiest quota you've used. Open it for one bar per quota, each with its reset date.

Every bar has a tick (`│`). The tick is your fair share for right now, where usage would sit if you spread it evenly to reset day. Fill behind the tick means you're on pace. Fill past it means you're burning faster than the clock, and the menu bar number warms from green to orange to red. At the worst state the gauge swaps to a warning triangle, so trouble reads without relying on color. Hit 100% and Ration stops pacing and counts down instead: see you on reset day.

## Install

### First-time checklist

Before installing, confirm these requirements:

- **App:** macOS, [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`), and `jq` (`brew install jq`).
- **Installer:** `git` is needed for the commands below. Homebrew is optional and only used by the example install commands.
- **Quota source:** Set up at least one quota source. Providers work independently, so you don't need all three:
  - **Copilot:** [GitHub CLI](https://cli.github.com/) signed in with `gh auth login` and an active Copilot seat.
  - **Codex:** a signed-in Codex app or CLI and one completed response. For the CLI, run `codex login` before using Codex.
  - **Antigravity:** Node.js/npm plus [`antigravity-usage`](https://github.com/skainguyen1412/antigravity-usage), installed with `npm install -g antigravity-usage` and signed in with `antigravity-usage login`.

Ration doesn't need API keys. It uses each provider's existing local sign-in or session data.

```bash
git clone https://github.com/shkao/ration.git
cd ration
./install.sh
```

Then point SwiftBar at the plugin folder `install.sh` prints (Preferences > Plugins > Plugin Folder). The default is `~/.swiftbar-plugins`; set `SWIFTBAR_PLUGIN_DIR` when running the installer to choose another folder. Coming from QuotaPace? `install.sh` clears the old plugin first, so SwiftBar won't run both.

### Reproducible setup

The checkout contains no account data or machine-specific settings. `install.sh` derives the helper, cache, and default plugin paths from each user's `HOME`; `SWIFTBAR_PLUGIN_DIR` is the only install setting. It copies the plugin and login helper but never copies quota caches or Codex sessions, so every installation reads that user's signed-in providers at runtime.

For the default layout on any account, run the same `./install.sh` command above and select the printed `~/.swiftbar-plugins` folder in SwiftBar. For a managed or shared folder, use the same explicit value on each machine:

```bash
SWIFTBAR_PLUGIN_DIR="$HOME/path/to/swiftbar-plugins" ./install.sh
```

## What it tracks

Ration shows a section for each provider you already use, and setup instructions when it finds none. Each provider works independently.

- **Copilot** needs the [GitHub CLI](https://cli.github.com/) (`gh`) signed in (`gh auth login`) with a Copilot seat. Ration reads your monthly premium-request quota and its reset date.
- **Codex** needs a signed-in Codex app or CLI and one completed response. Ration reads the usage windows in recent session snapshots under `~/.codex`, currently a five-hour and/or weekly limit depending on the account. It doesn't read credentials or make another API request.
- **Antigravity** needs the [`antigravity-usage`](https://github.com/skainguyen1412/antigravity-usage) CLI (`npm install -g antigravity-usage`, then a one-time `antigravity-usage login`). It reports two weekly quotas: all Gemini models share one, all Claude and GPT models share the other.

## Why "Ration"

A quota you set yourself is a budget. A quota your company hands you is a ration: someone else decided how much, it never feels like enough, and your job is making it last to the next distribution day.

That's the whole app. The tick is today's fair share. Fill past it is bread eaten early. Reset day is distribution day. And at 100%, Ration stops pretending there's anything left to pace and says what everyone at the back of the queue already knows: see you on reset day.

## How it works

Ration calls `gh api /copilot_internal/user`, the internal endpoint GitHub's own Copilot clients use, and refreshes every 5 minutes (the `5m` in `ration.5m.sh`, per SwiftBar's naming). It also reads the newest Codex rate-limit snapshot on disk. These sources report snapshots, so Ration works out pace locally from each limit's reset time and window length.

It caches the last good provider responses at `~/Library/Caches/ration/`. When GitHub is unreachable, the menu renders from that cache with an offline note and a wifi-slash icon instead of an error. A 15-second watchdog treats a stalled call as a network failure, so a bad connection falls back to the cache instead of hanging the refresh. Ration asks you to sign in when a previously detected Copilot account has no local token or GitHub rejects that token.

## Caveats

- `/copilot_internal/user` is undocumented and could change without notice.
- Pace assumes a monthly cycle starting one calendar month before the reset date. That's accurate for standard Copilot business and enterprise billing, but may not match unusual cycles.
- Codex usage updates only after Codex receives a response. ChatGPT web-chat model limits aren't stored in Codex sessions and have no supported usage endpoint, so Ration can't show them separately.
- The Antigravity section shows percentages only, because its CLI doesn't expose absolute request counts.

## Testing

```bash
./tests/run.sh
```

The suite runs the real plugin end to end against stub Copilot and Antigravity commands plus Codex session fixtures in an isolated `$HOME`. It covers provider combinations, pace escalation, exhausted states, Codex snapshot shapes, every error branch (offline, stalled calls, expired token, no Copilot seat, missing dependencies), concurrent fetches, both cache fallbacks, and installation into a custom per-user plugin folder. CI runs it on a macOS runner and ShellCheck on Linux.

## Uninstall

These commands use the default plugin folder. If you installed into a custom `SWIFTBAR_PLUGIN_DIR`, remove `ration.5m.sh` there instead.

```bash
rm ~/.swiftbar-plugins/ration.5m.sh
rm -rf ~/.ration-helpers ~/Library/Caches/ration
```

<details>
<summary>Project layout</summary>

```
ration.5m.sh              the plugin, everything in one file by design
helpers/ration-login.sh   "Sign in with GitHub…" recovery action
install.sh                copies both files into place
tests/run.sh              integration tests (provider fixtures, isolated $HOME)
.github/workflows/ci.yml  shellcheck on Linux, tests on macOS
```

SwiftBar runs a single file per plugin, so `ration.5m.sh` stays one self-contained script: no sourced libraries, no build step. It also runs every executable in its plugin folder as a plugin, so the login helper lives in `~/.ration-helpers/` instead. Left in the plugin folder, it would fire `gh auth login --web` on every launch.

</details>

## License

[MIT](LICENSE)
