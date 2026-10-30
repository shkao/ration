#!/bin/bash
# <xbar.title>Ration</xbar.title>
# <xbar.version>v3.1</xbar.version>
# <xbar.author>Allen Kao</xbar.author>
# <xbar.author.github>shkao</xbar.author.github>
# <xbar.desc>Rations your AI quotas: tracks Copilot, Codex, Claude, and Antigravity pace so they last until reset</xbar.desc>
# <xbar.dependencies>jq,awk</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Consistent decimal points regardless of the user's locale
export LC_ALL=C

# The `-` (not `:-`) fallbacks are test seams: the suite in tests/ overrides
# these with stubs, and setting an empty value simulates a missing dependency.
GH_BIN="${RATION_GH-$(command -v gh)}"
JQ_BIN="${RATION_JQ-$(command -v jq)}"
SECURITY_BIN="${RATION_SECURITY-$(command -v security)}"
CURL_BIN="${RATION_CURL-$(command -v curl)}"


# Adaptive "light_appearance,dark_appearance" colors — needed because any line
# using font= drops out of the native menu-item text color and defaults to a
# low-contrast color unless one is set explicitly.
SECONDARY_COLOR="#48484a,#aeaeb2"
# Status colors, tuned per appearance so light mode keeps >=4.5:1 contrast
# (single mid-brightness hexes like #f1c40f are unreadable on a light menu).
GREEN="#1a7f37,#3fb950"
YELLOW="#9a6700,#d29922"
ORANGE="#bc4c00,#f0883e"
RED="#d1242f,#f85149"
BLUE="#0969da,#58a6ff"

# Each provider's mark as a base64 PNG, black on transparent so SwiftBar's
# templateImage= tints it for the current appearance. 30px tall tagged 144 DPI:
# macOS reads the pHYs chunk and lays them out at 15pt, so they sit at menu bar
# scale while keeping retina pixels — untagged, they render at 30pt and tower
# over the percentage. Copilot, OpenAI, and Claude come from simple-icons, Antigravity
# from a threshold of its own app icon, since no icon set carries that mark.
# Inline because SwiftBar runs one file per plugin — a sidecar image folder
# would be picked up as a second plugin.
LOGO_COPILOT="iVBORw0KGgoAAAANSUhEUgAAAB4AAAAeCAQAAACROWYpAAAACXBIWXMAABYlAAAWJQFJUiTwAAACO0lEQVR4nMWUTWtTQRSGn9yEtKFF2yhNJQYXsS0VJO1KCyWiqAvdFgX1NyiibhTxF4hko6sus6guRNKSSmrtQsQfYNVWW2pBUXsJxZKkSZuM3GF6M/cjtSs9By7nvnPOzHs+ZuB/SaAF3sEoCXoR/OArbynvdcOz5KkiNK0wyZm/B8Z56QjTdZp468Ag91hvGWrpOncJ+uUc4Clj1JjiDUtU6Oc2R4AVHrJIhKOMcoEwz7iMcJ97CcECSQ0Zkaed1JAkCwjGvKRzCM650qhR02kC5xG88AavIOhyYZtsupBuBMveYNPTy7ik7a5wGXPHNLRTIrQ73EbkV88Z2ol42DBAA8FxB/ZKnjzjwFIIGgzokMG4dMyzz0buIFhjDcEtu6H7mZZ+403G/cxLaBHBBgWyTLCMoESaNCUES0yQpcCGbKfl+54+KzTGdzU/3TyRy5bWmWVYbj3MLHWF/uYxXcr+Rk+ALFcUA4tckD6ibPOFopbWAZKEKPKZOtjzlYUte3J1idFp253EHGtC6VbT1IOHqLJKm2rOKlWGfIJFs8/OhoRJcEjavSQIk/JzM/b4vvi+OIbfmFvZ+H6d8twqR17l0GQRJUdG2QEy5Ijaa4bynqLD+g3xQNZ8nquE2U3auCYHqsZ9/aqmmJH7mWRIqzo7w06RwZQ+hZ07oBfiNDe5KMlXeMcnfvFTdryHQU4QARpM8oi5VsQS3GCOsufpK/Ga6xx2Ovs/+iGOMchBWaYiJh/5wPau1fjH8gdqXu5Sxy7o3QAAAABJRU5ErkJggg=="
LOGO_CODEX="iVBORw0KGgoAAAANSUhEUgAAAB4AAAAeCAQAAACROWYpAAAACXBIWXMAABYlAAAWJQFJUiTwAAADGUlEQVR4nJXVW2jXZRgH8M/mYUu98JQtSy9a6GC01BSiA53sRERkVMTQi8xcFwahjCQCwYuUVkHuqoUYYRkpSQecLoqcTmhDmzmrxcBZEi1DbTn+m9ve+L3+9j/4T7Lnvfg9z/s+3+d9jr+XYipT6wu/GNBjp4f9D6rRKRSsAyquDHqTc4LjVpiFueqcEvRq8IFGL7j28tBJTgi2KcvujLe+wIshjSb/O3iN4KAJWXmpYxHSrl6tNT4yLOg0s9jh1/0pWJrKlXZHYKd787SqHBfsV5rbmqgx2gwGlET3N8kI/lBn3CWXXK1XsCIXV7MgY3tMVUKbY3RvmRalEs/40uqsmacEHWPgjYJTbjZXcCTuNOlVlZ4udiBN1hF3pn7+bcTUhL1expDFsTBj4Hftj98KW43ocLtH/CQY9aE5+FawIFGoj8VRBC5T7y9Bm6vS+9Y6KzjvVV2CmmQzyenjReCTfpax2WsyetJzZnnHSFrvaPKQ4JYicLDbjZG/wS5Bi+rUwMLYvv2uS4QWwX1F4NaC8nxlxAVvmx6lSfYImil1FPfEzQymmRGLM1oAHrHdS2p1ew4DluvzoFtLfYxVsaJ9Vpmi24t5DTpGwxrN069JJU7HFD+RHCRO7EmHYbotLhjVVgD92tb4PTyWZfcL9ibM7FiSwxalqtX2CT4zL0qVPhGKwEuSOU8a/IzymMV2Ta5Blwc8psoxb9ikS40TRWFU4veEqREctcF5wTnrTIzH5bEt+61XrqXo5vcFaxNmgeBQLNUOo4Juj7pNu1HbzI6ql4IXGZa5eDbViDPpzNyhIx2DNktSF+frKQBX+02wYSyCBLAs5UuttE9tnOvE8JuGBA1R+l6w06Dg09ycL48/uYv9k6NxVusTDGowJZo9m/Z1g/E5tVLfxKTNz4Pe7buo+nlaMu4SnLYxK2dpZmz3QTvUedI6rRH4g4fy/GgVvFxUtEiTbYnR5dYreW06IU5ab3T/MlTheY3e0+CkoMfK+FbM8HQMoT+b//+gOQ6m9yeVT9aPFl4ZNKESy+zyqyF9mj2b94pk6R/pgUWJre5IQQAAAABJRU5ErkJggg=="
LOGO_ANTIGRAVITY="iVBORw0KGgoAAAANSUhEUgAAACEAAAAeCAQAAAAIwb+cAAAACXBIWXMAABYlAAAWJQFJUiTwAAAB3klEQVR4nJWVz2sTQRiGn8R0TasghVrFENBbsCGth5raYNJjBVEx9aZ48iAiYo+lf4D3Qg+G5tDeehH0UC8ePKjYH5dSkdKAJVQRi0olFpuYrOw6nU53d3Y331wy3/vOM983TGZBH3085QsmP1jgJkdoO66yhinHTyYw2gMMsqkArLHHg3YA3bx0AKxR5UJ4xCNaHgiTmbAn0sOKJ8DkO8PhEGPUNQiTqTCADua1AJM1TgcjUnz2Qexxzbkg6kLkOOOzgcGVIESUQkCV+aBWklR82rDGb0b8qxggGVBFFzl/RD7EP+EycT3iGIOBAOjnnB5xnozD3uIvTUeul4vqNHZIvES3MtvkGe+pYZDhBgPKtnlmMb0KPMpz5eRfkFa0BFM0pPaRhHePab5K02vXBYtTkmqdojfiobRskfXQE7yTjhIRt6FLeWYmvPdglB3hqHDWLRek/JaTGkSMsvC0uO8UI7LTGtfRRx+fhO8NJw5L/WwJqUyHDwLGxaP4h9tq2mBOANZJBT7NC8K7zKmD9F127eQudwiOIVnxk/3neFh8M5pMOm6rLm6Jo6/937LAB3vaYJrjoQDW4T/ml73qG/dg0f65zTidIQFWRCmyYa/cgSVMVnUX1jeyvKJO9R88xQHabYBrtgAAAABJRU5ErkJggg=="
LOGO_CLAUDE="iVBORw0KGgoAAAANSUhEUgAAAB4AAAAeCAQAAACROWYpAAAACXBIWXMAABYlAAAWJQFJUiTwAAACoUlEQVQ4y43UTWyUVRQG4GegQKHaAjUyGlhIiMQaU1gQFmo0EhfG4IIFssAGQReaEBJdqCQmXRAqARNLXPiTsDEGbUzaBQFNGhNJTTG2LojlpwaRKD8j1gmhlpHaHhdep99MZ0jfu/nue973nnvvOd+lEjvcNCSfYRq9YoU5YKG/hNCV4Q4Lx+di5jch/GFJmflV6K8tnlc1/wi02lGO53G+HH9Jj/X1Mi8yKoTRtOw9Qtidoq8L4bRcpWWb9vT9rBDCVtAmhMdBh+lkrsC7wqQ30orHhXDGfDwpTGnGY26nZXdWmrsS3Wcp1ibZdmwXRrHS1aT5uPqky3yZQj9Zj/fTd4O3hM8t8l2KD2mcfVE5e5SEULLbvW6kDXYLex1O1qIH6t10ux+SqNeBlOdT4URiw5Y7tcgCb/s75Q9h2sWyMXyYUS700KwewSOGM4aZMaZVs03e9JkzJoWvWZJpxf/zd5bLMjOuGjGVmZfsy7lgtZKiPxUV3VB0xWWrddY52iXDhg065VbONq9qcbelFtcqQ8KUH500YMCVbIkq0WKexRptcbDK/LOCohImjBlz2rFaWVb5JHXxzLjmkFMmK7juauNd9pkQxnW7WSE9qkGTTTr1GxfCcNY438upg/u1GxGOVtiPaUrKBhs9l63zGt+mFtwlp0f4yk7hHf8I53wvDGqtdc4X0lZ63Y89wjV5XcIT6Td5UY9w1qrZ5iGhkB6AR9025Wn0CWstVxCuy9sv/OLBanObZywDeZeF/fjvOWzBViF8gQ7jCvVesQVOCgMacJ8wkfheITyPh434prb5PeGSlWCzcDHxeb8L1zWjSVst6wbTCuUzdQqD5dhm08IGdbFGj3Xl2QmhLxN9zZHapaqF88IHcxVXo8MFT91J8C/UgET8KuWWhgAAAABJRU5ErkJggg=="

# Deliberately outside the plugin folder: SwiftBar treats every executable in
# its plugin directory as its own plugin and runs it automatically, which
# previously caused this login script to auto-execute `gh auth login --web`
# on every SwiftBar launch instead of only when the user clicks the menu item.
LOGIN_SCRIPT="${HOME}/.ration-helpers/ration-login.sh"
BAR_WIDTH=16
PROVIDERS=("copilot" "codex" "claude" "antigravity")

# Last successful API response, so going offline shows stale data instead of errors.
CACHE_DIR="${HOME}/Library/Caches/ration"
CACHE_FILE="${CACHE_DIR}/quota.json"
CODEX_HOME="${HOME}/.codex"
CODEX_CACHE_FILE="${CACHE_DIR}/codex.tsv"

# Which quota drives the menu bar number: "auto" (busiest across providers) or
# "<provider>[-<scope>][:<limit>]", so a pinned tool stays readable without
# opening the dropdown. Kept outside the cache dir, so clearing caches doesn't
# reset it; the README's uninstall step removes it explicitly.
CONFIG_DIR="${HOME}/.config/ration"
MENUBAR_SOURCE_FILE="${CONFIG_DIR}/menubar-source"

# Optional allowlist of providers to show, one id per line. Unlisted providers
# are never fetched or rendered. A missing file, or one naming no known
# provider, keeps them all, so a typo can't blank the menu.
PROVIDERS_FILE="${CONFIG_DIR}/providers"
if [[ -s "$PROVIDERS_FILE" ]]; then
  ENABLED_PROVIDERS=()
  for provider in "${PROVIDERS[@]}"; do
    grep -qxE "[[:space:]]*${provider}[[:space:]]*" "$PROVIDERS_FILE" 2>/dev/null \
      && ENABLED_PROVIDERS+=("$provider")
  done
  (( ${#ENABLED_PROVIDERS[@]} > 0 )) && PROVIDERS=("${ENABLED_PROVIDERS[@]}")
fi

# The picker menu items re-run this same file with the flag below, which keeps
# the setting self-contained instead of needing a second helper script.
SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
if [[ "${1:-}" == "--set-menubar-source" ]]; then
  mkdir -p "$CONFIG_DIR" 2>/dev/null
  printf '%s\n' "${2:-auto}" > "$MENUBAR_SOURCE_FILE" 2>/dev/null
  exit 0
fi

# Provider contract: <id>_{fetch,export,postprocess,label,logo,has_data,rows,
# update_header,render,takeover,settings,present,welcome}. Main orchestration
# dispatches only through these hooks; source-specific behavior stays private.
# rows and update_header take an optional selector, "<scope>:<limit>" (see
# parse_menubar_source). Claude's account scopes are the one source-specific
# choice the picker and the menu bar title still spell out themselves.
provider_call() {
  local provider="$1" hook="$2"
  shift 2
  "${provider}_${hook}" "$@"
}

provider_any_data() { provider_any_data_except ""; }

provider_any_data_except() {
  local excluded="$1" provider
  for provider in "${PROVIDERS[@]}"; do
    [[ "$provider" == "$excluded" ]] && continue
    provider_call "$provider" has_data && return 0
  done
  return 1
}

provider_any_present() {
  local provider
  for provider in "${PROVIDERS[@]}"; do
    provider_call "$provider" present && return 0
  done
  return 1
}

# Decode the stored choice once into MENUBAR_PROVIDER, MENUBAR_SCOPE (a Claude
# account id or "each") and MENUBAR_LIMIT (a limit slug), and the selector the
# rows and update_header hooks take: "<scope>:<limit>", or empty for all rows.
# An unreadable or stale file (a provider that no longer exists) falls back to
# "auto" rather than pinning the menu bar to a source that can never report.
parse_menubar_source() {
  local value="auto" head provider
  [[ -s "$MENUBAR_SOURCE_FILE" ]] && value="$(sed -n '1p' "$MENUBAR_SOURCE_FILE" 2>/dev/null)"
  # Codex windows had ids of their own before every limit got a slug.
  case "$value" in
    codex-5-hours) value="codex:5-hours" ;;
    codex-weekly) value="codex:weekly" ;;
  esac
  MENUBAR_SOURCE="auto"
  MENUBAR_PROVIDER=""
  MENUBAR_SCOPE=""
  MENUBAR_LIMIT=""
  MENUBAR_SELECTOR=""
  head="${value%%:*}"
  for provider in "${PROVIDERS[@]}"; do
    [[ "$provider" == "${head%%-*}" ]] || continue
    MENUBAR_SOURCE="$value"
    MENUBAR_PROVIDER="$provider"
    [[ "$head" == *-* ]] && MENUBAR_SCOPE="${head#*-}"
    [[ "$value" == *:* ]] && MENUBAR_LIMIT="${value#*:}"
    [[ -n "${MENUBAR_SCOPE}${MENUBAR_LIMIT}" ]] && MENUBAR_SELECTOR="${MENUBAR_SCOPE}:${MENUBAR_LIMIT}"
    return 0
  done
}

# macOS has no `timeout`; without one a stalled network call would hang the
# SwiftBar refresh indefinitely. The watchdog's output goes to /dev/null so
# its sleep can't hold a caller's command-substitution pipe open, and its trap
# takes the sleep down with it, so a finished call leaves no process behind.
# `:-` so an empty override still means the default; tests shorten it via
# RATION_TIMEOUT.
FETCH_TIMEOUT="${RATION_TIMEOUT:-15}"
run_with_timeout() {
  "$@" &
  local cmd=$!
  (
    sleep "$FETCH_TIMEOUT" &
    sleeper=$!
    trap 'kill "$sleeper"; exit' TERM
    wait "$sleeper" && kill "$cmd"
  ) >/dev/null 2>&1 &
  local dog=$!
  local rc=0
  wait "$cmd" || rc=$?
  kill "$dog" 2>/dev/null
  return "$rc"
}

# True when $1 > $2, for floats (bash arithmetic is integer-only; avoids a bc dependency)
float_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 > b + 0) }'
}

# Make arbitrary error text safe for a SwiftBar line: "|" starts the parameter
# section and newlines start a new menu item, so both must go; long messages
# are truncated to keep the dropdown usable.
sanitize_error() {
  local text="${1//$'\n'/ }"
  text="${text//|/-}"
  printf '%.160s' "$text"
}

write_cache() {
  local path="$1" contents="$2"
  mkdir -p "$CACHE_DIR" 2>/dev/null
  printf '%s\n' "$contents" > "${path}.tmp" 2>/dev/null && mv -f "${path}.tmp" "$path" 2>/dev/null
}

# Marker is "│" (U+2502), not ASCII "|": a literal pipe would start the
# SwiftBar parameter section and break the line.
usage_bar() {
  local percent_left="$1"
  local pace_left="${2:-}"
  awk -v p="$percent_left" -v pace="$pace_left" -v width="$BAR_WIDTH" 'BEGIN {
    filled = int((p * width / 100) + 0.5)
    if (filled < 0) filled = 0
    if (filled > width) filled = width
    marker = -1
    if (pace != "") {
      marker = int((pace * width / 100) + 0.5)
      if (marker < 0) marker = 0
      if (marker > width - 1) marker = width - 1
    }
    bar = ""
    for (i = 0; i < width; i++) {
      if (i == marker) bar = bar "│"
      else if (i < filled) bar = bar "█"
      else bar = bar "░"
    }
    print bar
  }'
}

# "30 Oct 15:18": now, or the time $1 (an epoch or a file's mtime) names.
stamp() {
  date ${1:+-r "$1"} '+%-d %b %H:%M'
}

format_reset() {
  local reset_epoch="$1"
  if [[ -z "$reset_epoch" || "$reset_epoch" == "null" ]]; then
    echo "unknown"
    return
  fi

  local reset_day today_day
  reset_day="$(date -r "$reset_epoch" "+%Y-%m-%d" 2>/dev/null)"
  today_day="$(date "+%Y-%m-%d")"
  if [[ "$reset_day" == "$today_day" ]]; then
    date -r "$reset_epoch" "+%H:%M" 2>/dev/null
  else
    stamp "$reset_epoch" 2>/dev/null
  fi
}

print_limit_line() {
  local label="$1"
  local percent_used="$2"
  local color="$3"
  local pace_pct="${4:-}"
  local rounded bar
  rounded="$(printf '%.0f' "$percent_used")"
  bar="$(usage_bar "$rounded" "$pace_pct")"
  # %-11s fits the longest label ("Claude+GPT:") so bars align across sections
  printf '%-11s [%s] %3s%% used | font=Menlo size=11 color=%s tooltip="Tick = your fair share spent by now. Fill past it = borrowing from tomorrow."\n' \
    "${label}:" "$bar" "$rounded" "$color"
}

print_quota_rows() {
  local rows="$1" label used reset_epoch elapsed
  while IFS=$'\t' read -r label used reset_epoch elapsed; do
    [[ -z "$label" ]] && continue
    print_limit_line "$label" "$used" "$(pace_color "$used" "$elapsed")" "$elapsed"
    echo "Resets $(format_reset "$reset_epoch") | size=11 color=${SECONDARY_COLOR}"
  done <<< "$rows"
}

# Same thresholds as the Copilot menu bar status: color by how far usage
# runs ahead of the time already elapsed in the quota window.
pace_color() {
  local used="$1" elapsed="$2" diff
  if float_gt "$used" 99.999; then
    echo "$RED"
    return
  fi
  diff="$(awk -v u="$used" -v e="$elapsed" 'BEGIN { printf "%.4f", u - e }')"
  if float_gt "$diff" 30; then echo "$RED"
  elif float_gt "$diff" 15; then echo "$ORANGE"
  elif float_gt "$diff" 5; then echo "$YELLOW"
  else echo "$GREEN"
  fi
}

# Rank a status color by severity so the header can report the worst quota.
color_rank() {
  case "$1" in
    "$RED") echo 3 ;;
    "$ORANGE") echo 2 ;;
    "$YELLOW") echo 1 ;;
    *) echo 0 ;;
  esac
}

update_header_from_rows() {
  local provider="$1" rows="$2" label used elapsed quota_color quota_rank current_rank exhausted
  while IFS=$'\t' read -r label used _ elapsed; do
    [[ -z "$label" ]] && continue
    quota_color="$(pace_color "$used" "$elapsed")"
    quota_rank="$(color_rank "$quota_color")"
    current_rank="$(color_rank "$HEADER_COLOR")"
    exhausted=false
    float_gt "$used" 99.999 && exhausted=true
    if (( quota_rank > current_rank )) || [[ "$exhausted" == true && "$quota_rank" == "$current_rank" ]]; then
      HEADER_COLOR="$quota_color"
      if [[ "$exhausted" == true ]]; then
        HEADER_STATUS="${provider} ${label} exhausted · see you on reset day"
      else
        case "$quota_rank" in
          3) HEADER_STATUS="${provider} ${label} burning fast" ;;
          2) HEADER_STATUS="${provider} ${label} over pace" ;;
          1) HEADER_STATUS="${provider} ${label} slightly over pace" ;;
        esac
      fi
    fi
  done <<< "$rows"
}

# Highest used% across TSV quota rows on stdin, rounded; nothing when empty.
max_used_pct() {
  awk -F'\t' '$2 != "" && (!seen || $2 > max) { max = $2; seen = 1 }
    END { if (seen) printf "%.0f", max }'
}

# A stored choice names a limit by its label's slug ("5 hours" -> "5-hours"),
# safe as a click parameter. Every awk below shares this one rule, so the
# picker's values and the row filter can't drift apart.
readonly SLUG_AWK='function slug(s) { s = tolower(s); gsub(/ /, "-", s); return s }'

# Rows ($1) narrowed to the limit a selector ($2, "<scope>:<limit>") names; all
# of them without one. Fails when nothing is left, so a pin to a limit that is
# gone reports no quota data instead of another limit's number.
selected_rows() {
  local limit="${2#*:}" rows="$1"
  [[ -n "$limit" ]] && rows="$(awk -F'\t' -v wanted="$limit" "${SLUG_AWK}"' slug($1) == wanted' <<< "$1")"
  [[ -n "$rows" ]] && printf '%s\n' "$rows"
}

# "<slug><TAB><label>" for each distinct limit in the rows on stdin, in order.
limit_choices() {
  awk -F'\t' "${SLUG_AWK}"' $1 != "" && !seen[$1]++ { print slug($1) "\t" $1 }'
}

# Roll pace up into the HEADER_* globals. $1 limits the roll-up to a single
# provider (empty = all of them), and $2 optionally to one account or limit.
# That is how a pinned menu bar reports only the quota it names.
compute_header() {
  local only="$1" selector="${2:-}" provider
  HEADER_COLOR="$GREEN"
  HEADER_STATUS="On pace"
  HEADER_ICON=""
  for provider in "${PROVIDERS[@]}"; do
    [[ -n "$only" && "$provider" != "$only" ]] && continue
    provider_call "$provider" update_header "$selector"
  done
  if [[ -n "$only" ]]; then
    provider_call "$only" rows "$selector" >/dev/null && return 0
  else
    # Plural wording only earns its place when more than Copilot reports.
    if [[ "$HEADER_COLOR" == "$GREEN" && "$HEADER_STATUS" == "On pace" ]] && \
       provider_any_data_except "copilot"; then
      HEADER_STATUS="All rations on pace"
    fi
    provider_any_data && return 0
  fi
  HEADER_COLOR="$ORANGE"
  HEADER_STATUS="No quota data"
}

# Antigravity quota via the antigravity-usage CLI (npm). All Gemini models
# share one weekly quota and all Claude/GPT models another, so one row per
# group. Fetched before the header renders so the global status can include
# these quotas; state lands in the AGY_* globals.
AGY_STATE="absent" # absent (CLI not installed) | ok | error
AGY_ROWS=""        # one group per line: label, used%, reset epoch, elapsed%
AGY_EMAIL=""
AGY_ASOF=""
AGY_FETCHED=""
# One jq pass over a snapshot: email on the first line, then one TSV row per
# quota group. Empty output means the payload isn't a usable snapshot.
# Weekly rolling window: elapsed = share of the 7 days already gone. A cached
# snapshot whose reset has passed reads as an unused window, reset unknown.
parse_antigravity() {
  # shellcheck disable=SC2016
  "$JQ_BIN" -r '
    select((.models | length) > 0)
    | (.email // ""),
      (.models
       | map(select(.isAutocompleteOnly | not))
       | [["Gemini", map(select(.modelId | startswith("gemini")))],
          ["Claude+GPT", map(select(.modelId | test("^(claude|gpt)")))]][]
       | select(.[1] | length > 0)
       | (.[1][0].resetTime | fromdate) as $reset
       | if $reset <= now then [.[0], 0, "null", 0]
         else [.[0],
               ((1 - .[1][0].remainingPercentage) * 100),
               $reset,
               ((604800000 - .[1][0].timeUntilResetMs) / 604800000 * 100
                | if . < 0 then 0 elif . > 100 then 100 else . end)]
         end
       | @tsv)' 2>/dev/null
}

antigravity_fetch() {
  local agy_bin
  agy_bin="${RATION_AGY-$(command -v antigravity-usage)}"
  if [[ -z "$agy_bin" ]]; then
    # SwiftBar's PATH has no nvm shims; pick the newest nvm-installed copy.
    # shellcheck disable=SC2012
    agy_bin="$(ls -t "$HOME"/.nvm/versions/node/*/bin/antigravity-usage 2>/dev/null | head -1)"
  fi
  [[ -z "$agy_bin" ]] && return 0

  local agy_cache="${CACHE_DIR}/antigravity.json" json parsed=""
  json="$(run_with_timeout "$agy_bin" --json --refresh 2>/dev/null)"
  [[ -n "$json" ]] && parsed="$(parse_antigravity <<< "$json")"
  if [[ -n "$parsed" ]]; then
    write_cache "$agy_cache" "$json"
    AGY_FETCHED="$(stamp)"
  elif [[ -s "$agy_cache" ]]; then
    parsed="$(parse_antigravity < "$agy_cache")"
    if [[ -z "$parsed" ]]; then
      AGY_STATE="error"
      return 0
    fi
    AGY_ASOF="$(stamp "$agy_cache")"
  else
    AGY_STATE="error"
    return 0
  fi

  AGY_STATE="ok"
  AGY_EMAIL="${parsed%%$'\n'*}"
  AGY_ROWS=""
  [[ "$parsed" == *$'\n'* ]] && AGY_ROWS="${parsed#*$'\n'}"
}

antigravity_export() {
  declare -p AGY_STATE AGY_ROWS AGY_EMAIL AGY_ASOF AGY_FETCHED
}

antigravity_postprocess() { :; }
antigravity_label() { echo "Antigravity"; }
antigravity_logo() { echo "$LOGO_ANTIGRAVITY"; }
antigravity_has_data() { [[ "$AGY_STATE" == "ok" ]]; }
antigravity_rows() { antigravity_has_data && selected_rows "$AGY_ROWS" "${1:-}"; }
antigravity_update_header() {
  local rows
  rows="$(antigravity_rows "${1:-}")" && update_header_from_rows "$(antigravity_label)" "$rows"
}

antigravity_render() {
  [[ "$AGY_STATE" == "absent" ]] && return 0
  echo "---"
  echo "**Antigravity** | md=true size=13"
  if [[ "$AGY_STATE" == "error" ]]; then
    echo "Quota unavailable · try: antigravity-usage doctor | size=11 color=${ORANGE}"
    return 0
  fi

  print_quota_rows "$AGY_ROWS"

  [[ -n "$AGY_FETCHED" ]] && echo "Antigravity fetched at ${AGY_FETCHED} | size=11 color=${SECONDARY_COLOR}"
  local note="$AGY_EMAIL"
  [[ -n "$AGY_ASOF" ]] && note="${note:+${note} · }cached from ${AGY_ASOF}"
  [[ -n "$note" ]] && echo "${note} | size=11 color=${SECONDARY_COLOR}"
}

antigravity_takeover() { return 1; }
antigravity_settings() { :; }
antigravity_present() { [[ "$AGY_STATE" != "absent" ]]; }
antigravity_welcome() {
  echo "For Antigravity (Node.js/npm): | size=12"
  echo "npm install -g antigravity-usage && antigravity-usage login | font=Menlo size=11 color=${SECONDARY_COLOR}"
}

# Codex writes the rate limits returned with each response into its local
# session JSONL. These are Codex limits, not ChatGPT web model limits.
CODEX_STATE="absent" # absent | ok
CODEX_ROWS=""        # one window per line: label, used%, reset epoch, elapsed%
CODEX_PLAN=""
CODEX_ASOF=""
codex_candidate_files() {
  # A resumed session can live under any creation date, including the archive.
  # Sort metadata first so sessions older than the best snapshot need no reads.
  find "$CODEX_HOME/sessions" "$CODEX_HOME/archived_sessions" -type f -name '*.jsonl' \
    -exec stat -f $'%m\t%z\t%N' {} + 2>/dev/null | sort -t $'\t' -k1,1nr
}

codex_fetch() {
  local candidate_files signature cached_signature file modified _size snapshot parsed="" best=0
  candidate_files="$(codex_candidate_files)"
  [[ -z "$candidate_files" ]] && return 0
  signature="v2:$(printf '%s\n' "$candidate_files" | cksum | awk '{ print $1 ":" $2 }')"

  if [[ -s "$CODEX_CACHE_FILE" ]]; then
    cached_signature="$(sed -n '1p' "$CODEX_CACHE_FILE")"
    if [[ "$cached_signature" == "$signature" ]]; then
      parsed="$(sed -n '2p' "$CODEX_CACHE_FILE")"
    fi
  fi

  if [[ "$cached_signature" != "$signature" ]]; then
    while IFS=$'\t' read -r modified _size file; do
      [[ "$modified" -lt "$best" ]] && break
      # shellcheck disable=SC2016
      # A line Codex is still writing has no newline yet, and tail -r would
      # glue it onto the newest complete line, so terminate it first. -R with
      # fromjson? then skips it; a parse error would stop jq for the file.
      snapshot="$({ cat "$file" 2>/dev/null; echo; } | tail -r | "$JQ_BIN" -rR --argjson modified "$modified" '
        fromjson?
        | select(.type == "event_msg" and .payload.type == "token_count")
        | ((.timestamp // "" | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601?) // $modified) as $recorded
        | .payload.rate_limits
        | select(.limit_id == "codex" and .primary.used_percent != null)
        | [$recorded, (.plan_type // "__RATION_NO_PLAN__"),
           .primary.used_percent, .primary.window_minutes, .primary.resets_at,
           (.secondary.used_percent // ""), (.secondary.window_minutes // ""),
           (.secondary.resets_at // "")]
        | @tsv' 2>/dev/null | head -1)"
      if [[ -n "$snapshot" && "${snapshot%%$'\t'*}" -ge "$best" ]]; then
        parsed="$snapshot"
        best="${snapshot%%$'\t'*}"
      fi
    done <<< "$candidate_files"
    write_cache "$CODEX_CACHE_FILE" "${signature}"$'\n'"${parsed}"
  fi
  [[ -z "$parsed" ]] && return 0

  local primary_used primary_window primary_reset secondary_used secondary_window secondary_reset
  IFS=$'\t' read -r CODEX_ASOF CODEX_PLAN primary_used primary_window primary_reset \
    secondary_used secondary_window secondary_reset <<< "$parsed"
  [[ "$CODEX_PLAN" == "__RATION_NO_PLAN__" ]] && CODEX_PLAN=""
  local now elapsed label slot
  now="$(date +%s)"
  CODEX_ROWS=""
  for slot in primary secondary; do
    local used window reset
    if [[ "$slot" == "primary" ]]; then
      used="$primary_used"; window="$primary_window"; reset="$primary_reset"
    else
      used="$secondary_used"; window="$secondary_window"; reset="$secondary_reset"
    fi
    [[ -z "$used" || -z "$window" || -z "$reset" ]] && continue
    # A window that reset after the snapshot has no usage yet, and its next
    # reset is unknown until Codex reports again. "null", not empty: tab is
    # IFS whitespace, so an empty field would shift the ones after it.
    if (( reset <= now )); then
      used=0; reset="null"
    fi
    elapsed="$(awk -v now="$now" -v reset="$reset" -v minutes="$window" 'BEGIN {
      if (reset == "null") { printf "0"; exit }
      duration = minutes * 60
      value = (now - (reset - duration)) * 100 / duration
      if (value < 0) value = 0
      if (value > 100) value = 100
      printf "%.4f", value
    }')"
    case "$window" in
      300) label="5 hours" ;;
      10080) label="Weekly" ;;
      *) label="${window} min" ;;
    esac
    CODEX_ROWS+="${CODEX_ROWS:+$'\n'}${label}"$'\t'"${used}"$'\t'"${reset}"$'\t'"${elapsed}"
  done
  [[ -z "$CODEX_ROWS" ]] && return 0
  CODEX_STATE="ok"
}

codex_export() {
  declare -p CODEX_STATE CODEX_ROWS CODEX_PLAN CODEX_ASOF
}

codex_postprocess() { :; }
codex_label() { echo "Codex"; }
codex_logo() { echo "$LOGO_CODEX"; }
codex_has_data() { [[ "$CODEX_STATE" == "ok" ]]; }
codex_rows() { codex_has_data && selected_rows "$CODEX_ROWS" "${1:-}"; }
codex_update_header() {
  local rows
  rows="$(codex_rows "${1:-}")" && update_header_from_rows "$(codex_label)" "$rows"
}

codex_render() {
  [[ "$CODEX_STATE" != "ok" ]] && return 0
  echo "---"
  echo "**Codex** | md=true size=13"
  print_quota_rows "$CODEX_ROWS"
  local plan_display
  plan_display="$(awk -v plan="$CODEX_PLAN" 'BEGIN {
    if (plan == "") print "ChatGPT"
    else print "ChatGPT " toupper(substr(plan, 1, 1)) substr(plan, 2)
  }')"
  echo "${plan_display} · local Codex snapshot from $(stamp "$CODEX_ASOF") | size=11 color=${SECONDARY_COLOR}"
  echo "Updates after a Codex response | size=11 color=${SECONDARY_COLOR}"
}

codex_takeover() { return 1; }
codex_settings() { :; }
codex_present() { [[ "$CODEX_STATE" != "absent" ]]; }
codex_welcome() {
  echo "For Codex (signed-in local app or CLI): | size=12"
  echo "Complete one response to create a usage snapshot | size=11 color=${SECONDARY_COLOR}"
}

# Claude plan limits (Pro, Max, Team, Enterprise): the numbers Claude Code's
# /usage shows, shared with claude.ai. Claude Code keeps one Keychain item per
# config dir, "Claude Code-credentials" for ~/.claude plus an 8-hex suffix
# (sha256 of the path) for each CLAUDE_CONFIG_DIR, so every item is one
# signed-in account and a personal plus a work account need no Ration setup.
# Ration only reads the access token: refreshing it would rotate the token
# Claude Code holds, so an expired one waits for Claude Code to run again.
CLAUDE_STATE="absent" # absent | ok (at least one account found)
CLAUDE_IDS=()         # per account: Keychain suffix, or "default" for ~/.claude
CLAUDE_NAMES=()       # per account: Personal, or the Team/Enterprise org name
CLAUDE_PLANS=()
CLAUDE_ROWSETS=()     # per account: one limit per line: label, used%, reset epoch, elapsed%
CLAUDE_WARNINGS=()    # per account: why the rows are missing or stale
CLAUDE_NOTES=()       # per account: email and when the data was fetched
CLAUDE_API="https://api.anthropic.com/api/oauth"
# The usage endpoint rate-limits frequent polling, and a 5-hour window barely
# moves in a minute, so each account is asked at most once per interval.
CLAUDE_MIN_INTERVAL=300

claude_services() {
  "$SECURITY_BIN" dump-keychain 2>/dev/null \
    | sed -n 's/^ *"svce"<blob>="\(Claude Code-credentials\(-[0-9a-f]\{8\}\)\{0,1\}\)"$/\1/p' \
    | sort -u
}

# The token travels on curl's stdin, never in argv where `ps` would show it.
# Prints the body, then the HTTP status on a line of its own.
claude_request() {
  printf 'Authorization: Bearer %s\nanthropic-beta: oauth-2025-04-20\n' "$CLAUDE_TOKEN" \
    | "$CURL_BIN" -sS -H @- -w '\n%{http_code}' "${CLAUDE_API}/$1"
}

# One jq pass over {subscription, tier, profile, usage}: account name, plan,
# and email on the first three lines, then one TSV row per limit. Windows are
# fixed (5 hours, 7 days), so elapsed comes from the reset time. A window
# without a reset, or one past it in a cached snapshot, reads as unused.
parse_claude() {
  # shellcheck disable=SC2016
  "$JQ_BIN" -r '
    def epoch: sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
    (if .subscription == "team" or .subscription == "enterprise"
     then .profile.organization.name // "Team" else "Personal" end),
    ((.subscription // "" | if . == "" then "Claude" else (.[:1] | ascii_upcase) + .[1:] end)
     + ((.tier // "" | capture("_(?<n>[0-9]+x)$") | " " + .n) // "")),
    (.profile.account.email // ""),
    ([["5 hours", .usage.five_hour.utilization, .usage.five_hour.resets_at, 18000],
      ["Weekly", .usage.seven_day.utilization, .usage.seven_day.resets_at, 604800]]
     + [.usage.limits[]? | select(.kind == "weekly_scoped")
        | [(.scope.model.display_name // "Model"), .percent, .resets_at, 604800]]
     | .[] | select(.[1] != null)
     | (if .[2] == null then null else (.[2] | epoch) end) as $reset
     | if $reset == null or $reset <= now then [.[0], 0, "null", 0]
       else [.[0], .[1], $reset,
             ((now - ($reset - .[3])) / .[3] * 100
              | if . < 0 then 0 elif . > 100 then 100 else . end)]
       end
     | @tsv)' 2>/dev/null
}

claude_fetch_account() {
  local service="$1" cache creds token expires subscription tier now mtime=0
  local json="" warning="" fetched="" asof="" response status profile parsed
  cache="${CACHE_DIR}/claude${service#Claude Code-credentials}.json"
  creds="$("$SECURITY_BIN" find-generic-password -s "$service" -w 2>/dev/null)"
  # Process substitution, not a here-string: bash 3.2 backs a here-string
  # with a temp file, and this one would hold the token.
  IFS=$'\t' read -r token expires subscription tier < <(printf '%s' "$creds" \
    | "$JQ_BIN" -r '.claudeAiOauth | [(.accessToken // "-"), (.expiresAt // 0),
        (.subscriptionType // "-"), (.rateLimitTier // "-")] | @tsv' 2>/dev/null)
  [[ "$subscription" == "-" ]] && subscription=""
  [[ "$tier" == "-" ]] && tier=""
  now="$(date +%s)"
  [[ -s "$cache" ]] && mtime="$(stat -f %m "$cache" 2>/dev/null)"

  if (( now - mtime < CLAUDE_MIN_INTERVAL )); then
    json="$(cat "$cache")"
    fetched="$mtime"
  elif [[ -z "$token" || "$token" == "-" ]] || (( ${expires:-0} / 1000 <= now )); then
    warning="Sign-in expired · open Claude Code to refresh"
  else
    CLAUDE_TOKEN="$token"
    response="$(run_with_timeout claude_request usage 2>/dev/null)"
    status="${response##*$'\n'}"
    if [[ "$status" == "200" ]]; then
      profile="$(run_with_timeout claude_request profile 2>/dev/null)"
      if [[ "${profile##*$'\n'}" == "200" ]]; then
        profile="${profile%$'\n'*}"
      else
        profile="$("$JQ_BIN" -c '.profile // {}' "$cache" 2>/dev/null)"
      fi
      [[ -z "$profile" ]] && profile="{}"
      # shellcheck disable=SC2016
      json="$("$JQ_BIN" -cn --argjson usage "${response%$'\n'*}" --argjson profile "$profile" \
        --arg subscription "$subscription" --arg tier "$tier" \
        '{subscription: $subscription, tier: $tier, profile: $profile, usage: $usage}' 2>/dev/null)"
      if [[ -n "$json" ]]; then
        write_cache "$cache" "$json"
        fetched="$now"
      else
        warning="Unexpected response from the Claude usage API"
      fi
    elif [[ "$status" == "401" ]]; then
      warning="Sign-in expired · open Claude Code to refresh"
    elif [[ "$status" =~ ^[0-9]{3}$ && "$status" != "000" ]]; then
      warning="Claude usage API answered HTTP ${status}"
    else
      warning="Claude usage API is unreachable"
    fi
    unset CLAUDE_TOKEN
  fi

  if [[ -z "$json" && -s "$cache" ]]; then
    json="$(cat "$cache")"
    asof="$(stamp "$mtime")"
  fi
  # shellcheck disable=SC2016
  [[ -z "$json" ]] && json="$("$JQ_BIN" -cn --arg subscription "$subscription" --arg tier "$tier" \
    '{subscription: $subscription, tier: $tier}')"
  parsed="$(parse_claude <<< "$json")"
  [[ -z "$parsed" ]] && return 0

  local name plan email rows="" note
  { IFS= read -r name; IFS= read -r plan; IFS= read -r email; } <<< "$parsed"
  [[ "$(wc -l <<< "$parsed")" -gt 3 ]] && rows="$(sed '1,3d' <<< "$parsed")"
  [[ -z "$rows" && -z "$warning" ]] && warning="Unexpected response from the Claude usage API"
  note="$(sanitize_error "$email")"
  [[ -n "$fetched" ]] && note="${note:+${note} · }fetched at $(stamp "$fetched")"
  [[ -n "$asof" ]] && note="${note:+${note} · }cached from ${asof}"
  local id="${service#Claude Code-credentials-}"
  [[ "$id" == "$service" ]] && id="default"
  CLAUDE_IDS+=("$id")
  CLAUDE_NAMES+=("$(sanitize_error "$name")")
  CLAUDE_PLANS+=("$plan")
  CLAUDE_ROWSETS+=("$rows")
  CLAUDE_WARNINGS+=("$warning")
  CLAUDE_NOTES+=("$note")
}

claude_fetch() {
  [[ -z "$SECURITY_BIN" || -z "$CURL_BIN" ]] && return 0
  local services service
  services="$(claude_services)"
  while IFS= read -r service; do
    [[ -n "$service" ]] && claude_fetch_account "$service"
  done <<< "$services"
  (( ${#CLAUDE_NAMES[@]} > 0 )) && CLAUDE_STATE="ok"
}

claude_export() {
  declare -p CLAUDE_STATE CLAUDE_IDS CLAUDE_NAMES CLAUDE_PLANS CLAUDE_ROWSETS CLAUDE_WARNINGS CLAUDE_NOTES
}

claude_postprocess() { :; }
claude_label() { echo "Claude"; }
claude_logo() { echo "$LOGO_CLAUDE"; }
claude_has_data() {
  local rows
  for rows in "${CLAUDE_ROWSETS[@]}"; do
    [[ -n "$rows" ]] && return 0
  done
  return 1
}
# Account i's rows under a selector ($2): its scope is an account id, or empty
# or "each" for every account. An account without the limit reports nothing.
claude_account_rows() {
  local i="$1" scope="${2%%:*}"
  [[ -n "$scope" && "$scope" != "each" && "${CLAUDE_IDS[i]}" != "$scope" ]] && return 1
  [[ -n "${CLAUDE_ROWSETS[i]}" ]] && selected_rows "${CLAUDE_ROWSETS[i]}" "$2"
}
claude_rows() {
  local i found=1
  for i in "${!CLAUDE_ROWSETS[@]}"; do
    claude_account_rows "$i" "${1:-}" && found=0
  done
  return "$found"
}
# With two accounts, "Claude Weekly over pace" wouldn't say which plan is
# burning, so the account name joins the status.
claude_update_header() {
  local i name rows
  for i in "${!CLAUDE_NAMES[@]}"; do
    rows="$(claude_account_rows "$i" "${1:-}")" || continue
    name="$(claude_label)"
    (( ${#CLAUDE_NAMES[@]} > 1 )) && name+=" ${CLAUDE_NAMES[i]}"
    update_header_from_rows "$name" "$rows"
  done
}

claude_render() {
  [[ "$CLAUDE_STATE" != "ok" ]] && return 0
  echo "---"
  echo "**Claude** | md=true size=13"
  local i
  for i in "${!CLAUDE_NAMES[@]}"; do
    echo "${CLAUDE_NAMES[i]} · ${CLAUDE_PLANS[i]} | size=12"
    [[ -n "${CLAUDE_ROWSETS[i]}" ]] && print_quota_rows "${CLAUDE_ROWSETS[i]}"
    [[ -n "${CLAUDE_WARNINGS[i]}" ]] && echo "${CLAUDE_WARNINGS[i]} | size=11 color=${ORANGE}"
    [[ -n "${CLAUDE_NOTES[i]}" ]] && echo "${CLAUDE_NOTES[i]} | size=11 color=${SECONDARY_COLOR}"
  done
}

claude_account_name() {
  local i
  for i in "${!CLAUDE_IDS[@]}"; do
    [[ "${CLAUDE_IDS[i]}" == "$1" ]] && { echo "${CLAUDE_NAMES[i]}"; return 0; }
  done
  return 1
}

# The locale switch keeps a non-ASCII organization name's first letter whole.
first_letter() {
  local LC_ALL=en_US.UTF-8
  printf '%s' "${1:0:1}" | tr '[:lower:]' '[:upper:]'
}

# Every account's busiest quota side by side, "P 40% · A 62%" for the menu bar
# or with full names for its tooltip. A selector with a limit ($2) compares that
# one limit instead, and an account without it drops out rather than show
# another limit.
claude_each_title() {
  local style="$1" i name rows used parts=()
  for i in "${!CLAUDE_NAMES[@]}"; do
    rows="$(claude_account_rows "$i" "${2:-}")" || continue
    used="$(max_used_pct <<< "$rows")"
    name="${CLAUDE_NAMES[i]}"
    [[ "$style" == "initials" ]] && name="$(first_letter "$name")"
    parts+=("${name} ${used}%")
  done
  (( ${#parts[@]} > 0 )) || return 0
  printf '%s' "${parts[0]}"
  for i in "${parts[@]:1}"; do
    printf ' · %s' "$i"
  done
}

claude_takeover() { return 1; }
claude_settings() {
  if [[ "$CLAUDE_STATE" == "ok" ]]; then
    echo "Open Claude usage | href=https://claude.ai/settings/usage sfimage=gearshape"
  fi
}
claude_present() { [[ "$CLAUDE_STATE" != "absent" ]]; }
claude_welcome() {
  echo "For Claude (Pro, Max, Team, or Enterprise plan): | size=12"
  echo "Sign in to Claude Code with /login | font=Menlo size=11 color=${SECONDARY_COLOR}"
}

# Shared chrome for full-menu (takeover) screens: menu bar glyph, app header,
# headline, optional extra lines, refresh action. Callers pass complete
# SwiftBar lines; this owns only the skeleton around them.
print_takeover_menu() {
  local title="$1" headline="$2"
  shift 2
  echo "$title"
  echo "---"
  echo "Ration | size=13"
  echo "$headline"
  local line
  for line in "$@"; do
    echo "$line"
  done
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
}

signin_item() {
  echo "Sign in with GitHub… | bash=${LOGIN_SCRIPT} color=${BLUE} size=12 sfimage=person.crop.circle.badge.plus"
}

# `terminal=false` keeps the click silent, `refresh=true` re-renders the menu
# bar with the new source immediately. SELF is quoted for plugin folders with
# spaces in their path.
menubar_source_params() {
  local value="$1"
  local params="bash=\"${SELF}\" param1=--set-menubar-source param2=${value} terminal=false refresh=true"
  [[ "$value" == "$MENUBAR_SOURCE" ]] && params+=" checked=true"
  echo "$params"
}

# "Claude · each account · Weekly": the tool, then its account and limit.
menubar_source_name() {
  local name slug label label_found
  [[ -z "$MENUBAR_PROVIDER" ]] && { echo "Busiest quota"; return; }
  name="$(provider_call "$MENUBAR_PROVIDER" label)"
  case "$MENUBAR_SCOPE" in
    "") ;;
    each) name+=" · each account" ;;
    *) name+=" · $(claude_account_name "$MENUBAR_SCOPE" || echo "signed out")" ;;
  esac
  [[ -z "$MENUBAR_LIMIT" ]] && { echo "$name"; return; }
  # A limit nothing reports any more still reads as words, not as a slug.
  label="${MENUBAR_LIMIT//-/ }"
  while IFS=$'\t' read -r slug label_found; do
    [[ "$slug" == "$MENUBAR_LIMIT" ]] && label="$label_found"
  done <<< "$(provider_call "$MENUBAR_PROVIDER" rows | limit_choices)"
  echo "${name} · ${label}"
}

# Only providers that are set up are offered, plus whichever one is pinned, so
# the current choice always shows its checkmark even after a provider drops out.
# A tool with several choices gets its own section under a dimmed name, so each
# row only says what differs ("5 hours", "Personal") instead of repeating the
# tool and its logo. A tool with one choice is a single named row.
#
# Which account and which limit are separate questions, so each gets its own
# group with its own checkmark, and a click in one keeps the other's answer:
# every row's value is the current choice with only its own half swapped.
print_menubar_source_menu() {
  local provider label choices scope limit slug i
  echo "Indicator: $(menubar_source_name) | sfimage=menubar.rectangle"
  echo "--Busiest quota | $(menubar_source_params auto) tooltip=\"Automatically follows the highest usage across all providers\""
  for provider in "${PROVIDERS[@]}"; do
    [[ "$provider" == "$MENUBAR_PROVIDER" ]] || provider_call "$provider" present || continue
    label="$(provider_call "$provider" label)"
    choices="$(provider_call "$provider" rows | limit_choices)"
    scope=""
    limit=""
    if [[ "$provider" == "$MENUBAR_PROVIDER" ]]; then
      scope="${MENUBAR_SCOPE:+-${MENUBAR_SCOPE}}"
      limit="${MENUBAR_LIMIT:+:${MENUBAR_LIMIT}}"
    fi
    echo "-----"
    if [[ "$provider" == "claude" ]] && (( ${#CLAUDE_IDS[@]} > 1 )); then
      echo "--${label} | size=12"
      echo "--Busiest account | $(menubar_source_params "claude${limit}") tooltip=\"Automatically follows the busiest Claude account\""
      echo "--Each account | $(menubar_source_params "claude-each${limit}") tooltip=\"Shows every account side by side\""
      for i in "${!CLAUDE_IDS[@]}"; do
        echo "--${CLAUDE_NAMES[i]} | $(menubar_source_params "claude-${CLAUDE_IDS[i]}${limit}")"
      done
      [[ -n "$choices" ]] && echo "--Limit | size=12"
    elif [[ "$choices" == *$'\n'* || -n "$limit" ]]; then
      echo "--${label} | size=12"
    else
      echo "--${label} | $(menubar_source_params "$provider")"
      continue
    fi
    [[ -z "$choices" ]] && continue
    echo "--Busiest limit | $(menubar_source_params "${provider}${scope}") tooltip=\"Automatically follows the highest ${label} limit\""
    while IFS=$'\t' read -r slug label; do
      echo "--${label} | $(menubar_source_params "${provider}${scope}:${slug}")"
    done <<< "$choices"
  done
}

# jq parses every provider's output, so it stays a hard requirement. gh is
# only needed for Copilot; its absence just means that provider isn't shown.
if [[ -z "$JQ_BIN" ]]; then
  print_takeover_menu "? | sfimage=gauge" \
    "Missing dependencies: jq | color=${RED} size=12" \
    "brew install jq | font=Menlo size=11 color=${SECONDARY_COLOR}"
  exit 0
fi

# One-click recovery path instead of a dead-end error.
print_signin_menu() {
  local headline="$1"
  local -a extras=("---")
  if [[ -x "$LOGIN_SCRIPT" ]]; then
    extras+=("$(signin_item)" "Opens a one-time code in your browser | size=10 color=${SECONDARY_COLOR}")
  else
    # install.sh wasn't run, so the login helper isn't available — a dead
    # menu item would be worse than pointing at the terminal command.
    extras+=("Run in a terminal: | size=12" "gh auth login --web | font=Menlo size=11 color=${SECONDARY_COLOR}")
  fi
  print_takeover_menu "? | sfimage=person.crop.circle.badge.exclamationmark sfcolor=${RED}" \
    "${headline} | color=${RED} size=12" "${extras[@]}"
}

# GitHub Copilot quota via `gh api`. Detection rule: the provider counts as
# "in use" when gh is installed and signed in, or when a previous run left a
# cache (so a signed-out Copilot user gets a re-login prompt instead of a
# silently vanished section). No gh, no token, no cache: no Copilot section.
CP_STATE="absent" # absent | ok | offline | signedout | expired | nocopilot | unreachable | badresponse
CP_ERR=""
OFFLINE_ASOF=""
CP_FETCHED=""
RESPONSE=""
# Single home for state copy rendered both as a section line and a takeover menu.
CP_MSG_UNREACHABLE="GitHub is unreachable and no cached data yet"
CP_MSG_BADRESPONSE="Unexpected response from Copilot API"
copilot_fetch() {
  [[ -z "$GH_BIN" ]] && return 0

  # `gh auth token` only reads local credentials; `gh auth status` hits the
  # network, so it would misreport "not signed in" whenever the machine is offline.
  if ! "$GH_BIN" auth token >/dev/null 2>&1; then
    [[ -s "$CACHE_FILE" ]] && CP_STATE="signedout"
    return 0
  fi

  # stderr kept apart: a gh warning mixed into a good response would make it
  # unparsable. Errors still need it, since gh reports the HTTP status there.
  local err_file gh_err=""
  err_file="$(mktemp "${TMPDIR:-/tmp}/ration-gh.XXXXXX" 2>/dev/null)"
  RESPONSE="$(run_with_timeout "$GH_BIN" api /copilot_internal/user 2>"${err_file:-/dev/null}")"
  local api_exit=$?
  if [[ -n "$err_file" ]]; then
    gh_err="$(cat "$err_file")"
    rm -f "$err_file"
  fi
  [[ $api_exit -ne 0 ]] && RESPONSE="${gh_err}${gh_err:+${RESPONSE:+ }}${RESPONSE}"
  # A watchdog kill leaves no output; give the error screens something to show.
  [[ $api_exit -ne 0 && -z "$RESPONSE" ]] && RESPONSE="gh api gave no response within ${FETCH_TIMEOUT}s"
  if [[ $api_exit -ne 0 ]]; then
    if echo "$RESPONSE" | grep -q "HTTP 401"; then
      # The local token exists but GitHub rejected it — only here is re-login the fix.
      CP_STATE="expired"
      return 0
    elif echo "$RESPONSE" | grep -qE "HTTP (403|404)"; then
      # Signed in to GitHub, but this account/org has no Copilot access.
      CP_STATE="nocopilot"
      return 0
    elif [[ -s "$CACHE_FILE" ]]; then
      # Network trouble (offline, DNS, GitHub down): render the last good
      # snapshot instead of an error; the cache mtime is when it was fetched.
      RESPONSE="$(cat "$CACHE_FILE")"
      OFFLINE_ASOF="$(stamp "$CACHE_FILE")"
      CP_STATE="offline"
    else
      CP_STATE="unreachable"
      CP_ERR="$(sanitize_error "$RESPONSE")"
      return 0
    fi
  else
    CP_STATE="ok"
    CP_FETCHED="$(stamp)"
  fi
}

copilot_export() {
  declare -p CP_STATE CP_ERR OFFLINE_ASOF RESPONSE CP_FETCHED
}

# Parse the (fresh or cached) response and derive pace. Sets CP_STATE to
# badresponse when the payload doesn't look like a Copilot quota snapshot.
copilot_postprocess() {
copilot_has_data || return 0
# IFS must be a tab: fields like the org name can contain spaces, and default
# word splitting would shift every field after them.
IFS=$'\t' read -r LOGIN REMAINING ENTITLEMENT PERCENT_REMAINING RESET_UTC PLAN ORG <<EOF
$(echo "$RESPONSE" | "$JQ_BIN" -r '
  [
    .login,
    .quota_snapshots.premium_interactions.quota_remaining,
    .quota_snapshots.premium_interactions.entitlement,
    .quota_snapshots.premium_interactions.percent_remaining,
    .quota_reset_date_utc,
    .copilot_plan,
    (.organization_list[0].name // "personal")
  ] | @tsv')
EOF

if [[ -z "$PERCENT_REMAINING" || "$PERCENT_REMAINING" == "null" ]]; then
  CP_STATE="badresponse"
  CP_ERR="$(sanitize_error "$RESPONSE")"
  return 0
fi

# Only a fresh, validated response refreshes the cache; atomic so a killed
# run can't leave a truncated file behind.
if [[ -z "$OFFLINE_ASOF" ]]; then
  write_cache "$CACHE_FILE" "$RESPONSE"
fi

# Billing period end = quota_reset_date_utc; assume a monthly cycle, so
# period start = one calendar month before the reset (Copilot business/enterprise
# quotas reset on a fixed monthly cadence, not a rolling window).
RESET_CLEAN="${RESET_UTC%%.*}"
EPOCH_END=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$RESET_CLEAN" "+%s" 2>/dev/null)
EPOCH_START=$(date -j -u -v-1m -f "%Y-%m-%dT%H:%M:%S" "$RESET_CLEAN" "+%s" 2>/dev/null)
EPOCH_NOW=$(date -u +%s)

ACTUAL_USED_PCT=$(awk -v p="$PERCENT_REMAINING" 'BEGIN { printf "%.4f", 100 - p }')

if [[ -n "$EPOCH_END" && -n "$EPOCH_START" && "$EPOCH_END" -gt "$EPOCH_START" ]]; then
  ELAPSED_PCT=$(awk -v now="$EPOCH_NOW" -v s="$EPOCH_START" -v e="$EPOCH_END" \
    'BEGIN { v = (now - s) * 100 / (e - s); if (v < 0) v = 0; if (v > 100) v = 100; printf "%.4f", v }')
else
  ELAPSED_PCT=""
fi

# A cached snapshot from before the reset says nothing about the new month:
# show a full ration with the reset unknown, as the other providers do.
if [[ -n "$OFFLINE_ASOF" && -n "$EPOCH_END" ]] && (( EPOCH_END <= EPOCH_NOW )); then
  ACTUAL_USED_PCT=0
  PERCENT_REMAINING=100
  REMAINING="$ENTITLEMENT"
  EPOCH_END="null"
  ELAPSED_PCT=""
fi

# format_reset always yields text ("unknown" when the epoch is unparsable).
RESET_DISPLAY="$(format_reset "$EPOCH_END")"

# Menu bar color + status, based on pace (usage rate vs. time elapsed in the month)
COLOR="$GREEN"
STATUS="On pace"
if [[ -n "$ELAPSED_PCT" ]]; then
  COLOR="$(pace_color "$ACTUAL_USED_PCT" "$ELAPSED_PCT")"
  case "$(color_rank "$COLOR")" in
    3) STATUS="Burning through the ration · may run out before reset" ;;
    2) STATUS="Over pace" ;;
    1) STATUS="Slightly over pace" ;;
  esac
else
  if float_gt 20 "$PERCENT_REMAINING"; then
    COLOR="$RED"; STATUS="Ration running low"
  elif float_gt 50 "$PERCENT_REMAINING"; then
    COLOR="$YELLOW"; STATUS="Watch the ration"
  fi
fi

# The state this app is named for: nothing left to pace, only the wait.
if ! float_gt "$PERCENT_REMAINING" 0; then
  COLOR="$RED"
  STATUS="Ration exhausted · see you on reset day"
fi
}

copilot_label() { echo "Copilot"; }
copilot_logo() { echo "$LOGO_COPILOT"; }

copilot_has_data() { [[ "$CP_STATE" == "ok" || "$CP_STATE" == "offline" ]]; }

copilot_rows() {
  copilot_has_data && printf 'Monthly\t%s\t%s\t%s\n' "$ACTUAL_USED_PCT" "$EPOCH_END" "$ELAPSED_PCT"
}

copilot_update_header() {
  if copilot_has_data; then
    HEADER_COLOR="$COLOR"
    HEADER_STATUS="$STATUS"
  fi
  [[ -n "$OFFLINE_ASOF" ]] && HEADER_ICON="wifi.slash"
}

copilot_render() {
  case "$CP_STATE" in absent | nocopilot) return 0 ;; esac
  if [[ -n "$OFFLINE_ASOF" ]]; then
    echo "Offline · cached data from ${OFFLINE_ASOF} | size=11 color=${SECONDARY_COLOR}"
  fi
  echo "---"
  echo "**Copilot** | md=true size=13"
  case "$CP_STATE" in
    ok | offline)
      # Usage-style bar: fill = quota used, tick = share of the billing month
      # already elapsed. Fill past the tick means burning faster than time
      # passes. Tick is skipped when the billing period couldn't be derived.
      print_limit_line "Monthly" "$ACTUAL_USED_PCT" "$COLOR" "$ELAPSED_PCT"
      echo "Resets ${RESET_DISPLAY} · $(printf '%.0f' "$REMAINING") of ${ENTITLEMENT} left | size=11 color=${SECONDARY_COLOR}"
      echo "${LOGIN} · ${PLAN} (${ORG}) | size=11 color=${SECONDARY_COLOR}"
      [[ -n "$CP_FETCHED" ]] && echo "Copilot fetched at ${CP_FETCHED} | size=11 color=${SECONDARY_COLOR}"
      ;;
    signedout | expired)
      local headline="Not signed in to GitHub"
      [[ "$CP_STATE" == "expired" ]] && headline="GitHub sign-in expired"
      echo "${headline} | size=11 color=${ORANGE}"
      if [[ -x "$LOGIN_SCRIPT" ]]; then
        signin_item
      else
        echo "gh auth login --web | font=Menlo size=11 color=${SECONDARY_COLOR}"
      fi
      ;;
    unreachable)
      echo "${CP_MSG_UNREACHABLE} | size=11 color=${ORANGE}"
      ;;
    badresponse)
      echo "${CP_MSG_BADRESPONSE} | size=11 color=${ORANGE}"
      echo "${CP_ERR} | font=Menlo size=10 color=${SECONDARY_COLOR}"
      ;;
  esac
}

copilot_takeover() {
  provider_any_data_except "copilot" && return 1
  case "$CP_STATE" in
    signedout)
      print_signin_menu "Not signed in to GitHub"
      ;;
    expired)
      print_signin_menu "GitHub sign-in expired"
      ;;
    nocopilot)
      print_takeover_menu "? | sfimage=exclamationmark.shield sfcolor=${ORANGE}" \
        "GitHub Copilot isn't enabled for this account | color=${ORANGE} size=12" \
        "---" \
        "Open Copilot settings | href=https://github.com/settings/copilot color=${BLUE} size=12 sfimage=gearshape"
      ;;
    unreachable)
      print_takeover_menu "? | sfimage=wifi.slash sfcolor=${ORANGE}" \
        "${CP_MSG_UNREACHABLE} | color=${ORANGE} size=12" \
        "${CP_ERR} | font=Menlo size=10 color=${SECONDARY_COLOR}"
      ;;
    badresponse)
      print_takeover_menu "? | sfimage=gauge" \
        "${CP_MSG_BADRESPONSE} | color=${RED} size=12" \
        "${CP_ERR} | font=Menlo size=10 color=${SECONDARY_COLOR}"
      ;;
    *) return 1 ;;
  esac
  return 0
}

copilot_settings() {
  if [[ "$CP_STATE" != "absent" ]]; then
    echo "Open Copilot settings | href=https://github.com/settings/copilot sfimage=gearshape"
  fi
}

copilot_present() { [[ "$CP_STATE" != "absent" ]]; }
copilot_welcome() {
  local hint="brew install gh && gh auth login --web | font=Menlo size=11 color=${SECONDARY_COLOR}"
  [[ -n "$GH_BIN" && -x "$LOGIN_SCRIPT" ]] && hint="$(signin_item)"
  echo "For GitHub Copilot (GitHub CLI + active Copilot seat): | size=12"
  echo "$hint"
}

# First-run guidance when no provider is detected at all.
print_welcome_menu() {
  local provider welcome_lines=()
  for provider in "${PROVIDERS[@]}"; do
    welcome_lines+=("$(provider_call "$provider" welcome)")
  done
  print_takeover_menu "? | size=12.5 sfimage=gauge" \
    "First-time setup · choose at least one quota source | color=${ORANGE} size=12" \
    "---" \
    "App requirements | size=12" \
    "macOS · SwiftBar · jq | size=11 color=${SECONDARY_COLOR}" \
    "Quota source · set up one below | size=12" \
    "${welcome_lines[@]}"
}

PROVIDER_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ration.XXXXXX" 2>/dev/null)"
if [[ -n "$PROVIDER_STATE_DIR" ]]; then
  trap 'rm -rf "$PROVIDER_STATE_DIR"' EXIT
  PROVIDER_PIDS=()
  for provider in "${PROVIDERS[@]}"; do
    (
      provider_call "$provider" fetch
      provider_call "$provider" export > "$PROVIDER_STATE_DIR/$provider"
    ) &
    PROVIDER_PIDS+=("$!")
  done
  for pid in "${PROVIDER_PIDS[@]}"; do
    wait "$pid"
  done
  for provider in "${PROVIDERS[@]}"; do
    # shellcheck disable=SC1090
    source "$PROVIDER_STATE_DIR/$provider"
  done
  rm -rf "$PROVIDER_STATE_DIR"
  trap - EXIT
else
  for provider in "${PROVIDERS[@]}"; do
    provider_call "$provider" fetch
  done
fi
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" postprocess
done

for provider in "${PROVIDERS[@]}"; do
  if provider_call "$provider" takeover; then
    exit 0
  fi
done
if ! provider_any_present; then
  print_welcome_menu
  exit 0
fi

parse_menubar_source

# A pinned source owns the menu bar alone: naming one tool up there while
# coloring it by another's pace would be a lie. The dropdown header, computed
# second, still speaks for every provider — worst pace wins and names its
# quota in text so the alert doesn't rely on color alone.
compute_header "$MENUBAR_PROVIDER" "$MENUBAR_SELECTOR"
TITLE_COLOR="$HEADER_COLOR"
TITLE_STATUS="$HEADER_STATUS"
TITLE_OFFLINE_ICON="$HEADER_ICON"
[[ -n "$MENUBAR_PROVIDER" ]] && compute_header ""

# Menu bar percent: the selected account or limit when one is pinned, otherwise the busiest quota of the pinned provider or of every
# provider in "auto".
PERCENT_TITLE="$({
  for provider in "${PROVIDERS[@]}"; do
    [[ -n "$MENUBAR_PROVIDER" && "$provider" != "$MENUBAR_PROVIDER" ]] && continue
    provider_call "$provider" rows "$MENUBAR_SELECTOR"
  done
} | max_used_pct)"
TITLE_VALUE=""
[[ -n "$PERCENT_TITLE" ]] && TITLE_VALUE="${PERCENT_TITLE}%"
TITLE_DETAIL="${TITLE_VALUE} used"
if [[ "$MENUBAR_PROVIDER" == "claude" && "$MENUBAR_SCOPE" == "each" ]]; then
  TITLE_VALUE="$(claude_each_title initials "$MENUBAR_SELECTOR")"
  TITLE_DETAIL="$(claude_each_title names "$MENUBAR_SELECTOR") used"
fi

# A pinned percentage needs to say which tool it came from. The mark does that
# in the menu bar; the name still carries the tooltip and the text fallback.
TITLE_NAME=""
if [[ -n "$MENUBAR_PROVIDER" ]]; then
  TITLE_NAME="$(provider_call "$MENUBAR_PROVIDER" label) "
  [[ "$MENUBAR_PROVIDER" == "claude" && -n "$MENUBAR_SCOPE" && "$MENUBAR_SCOPE" != "each" && \
     ${#CLAUDE_IDS[@]} -gt 1 ]] && TITLE_NAME+="$(claude_account_name "$MENUBAR_SCOPE") "
  # Row-level statuses lead with the provider name, which the title already
  # carries: "Codex · Codex 5 hours over pace" reads as a stutter.
  TITLE_STATUS="${TITLE_STATUS#"$TITLE_NAME"}"
fi

# Smaller than the native menu bar font size (14) — per user preference.
TITLE_PARAMS="size=12.5"
# Surface off-pace states in the menu bar itself via the alert color.
if [[ "$TITLE_COLOR" == "$RED" || "$TITLE_COLOR" == "$ORANGE" ]]; then
  TITLE_PARAMS+=" color=${TITLE_COLOR}"
fi
# Gauge glyph gives the bare percentage an identity next to other numeric
# menu bar items. Red swaps in a warning glyph so the worst state doesn't
# rely on color alone; offline keeps its wifi-slash.
TITLE_ICON="gauge"
[[ "$TITLE_COLOR" == "$RED" ]] && TITLE_ICON="exclamationmark.triangle"
[[ -n "$TITLE_OFFLINE_ICON" ]] && TITLE_ICON="$TITLE_OFFLINE_ICON"
# A pinned provider swaps the generic gauge for its own mark, which says which
# tool the number belongs to more compactly than its name — so the name drops
# out of the title. The warning and offline glyphs still win that slot: they
# carry states the mark can't, and the name comes back to keep them readable.
TITLE_LABEL="$TITLE_NAME"
if [[ -n "$MENUBAR_PROVIDER" && "$TITLE_ICON" == "gauge" ]]; then
  TITLE_PARAMS+=" templateImage=$(provider_call "$MENUBAR_PROVIDER" logo)"
  TITLE_LABEL=""
else
  TITLE_PARAMS+=" sfimage=${TITLE_ICON}"
fi
TITLE_TOOLTIP="Ration · ${TITLE_NAME}${TITLE_STATUS}"
[[ -n "$TITLE_VALUE" ]] && TITLE_TOOLTIP="Ration · ${TITLE_NAME}${TITLE_DETAIL} · ${TITLE_STATUS}"
TITLE_PARAMS+=" tooltip=\"${TITLE_TOOLTIP}\""
if [[ -n "$TITLE_VALUE" ]]; then
  echo "${TITLE_LABEL}${TITLE_VALUE} | ${TITLE_PARAMS}"
else
  echo "${TITLE_LABEL}? | ${TITLE_PARAMS}"
fi
echo "---"
echo "Ration | size=13"
echo "● ${HEADER_STATUS} | color=${HEADER_COLOR} size=11"
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" render
done
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
print_menubar_source_menu
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" settings
done
