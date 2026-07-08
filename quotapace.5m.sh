#!/bin/bash
# <xbar.title>QuotaPace</xbar.title>
# <xbar.version>v2.4</xbar.version>
# <xbar.author>Allen Kao</xbar.author>
# <xbar.author.github>shkao</xbar.author.github>
# <xbar.desc>Tracks GitHub Copilot and Google Antigravity quota pace</xbar.desc>
# <xbar.dependencies>gh,jq,awk</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Consistent decimal points regardless of the user's locale
export LC_ALL=C

# The `-` (not `:-`) fallbacks are test seams: the suite in tests/ overrides
# these with stubs, and setting an empty value simulates a missing dependency.
GH_BIN="${QUOTAPACE_GH-$(command -v gh)}"
JQ_BIN="${QUOTAPACE_JQ-$(command -v jq)}"


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

# Deliberately outside the plugin folder: SwiftBar treats every executable in
# its plugin directory as its own plugin and runs it automatically, which
# previously caused this login script to auto-execute `gh auth login --web`
# on every SwiftBar launch instead of only when the user clicks the menu item.
LOGIN_SCRIPT="${HOME}/.quotapace-helpers/quotapace-login.sh"
BAR_WIDTH=16

# Last successful API response, so going offline shows stale data instead of errors.
CACHE_DIR="${HOME}/Library/Caches/quotapace"
CACHE_FILE="${CACHE_DIR}/quota.json"

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
    date -r "$reset_epoch" "+%-d %b %H:%M" 2>/dev/null
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
  printf '%-11s [%s] %3s%% used | font=Menlo size=11 color=%s\n' \
    "${label}:" "$bar" "$rounded" "$color"
}

# Same thresholds as the Copilot menu bar status: color by how far usage
# runs ahead of the time already elapsed in the quota window.
pace_color() {
  local used="$1" elapsed="$2" diff
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

# Antigravity quota via the antigravity-usage CLI (npm). All Gemini models
# share one weekly quota and all Claude/GPT models another, so one row per
# group. Fetched before the header renders so the global status can include
# these quotas; state lands in the AGY_* globals.
AGY_STATE="absent" # absent (CLI not installed) | ok | error
AGY_ROWS=""        # one group per line: label, used%, reset epoch, elapsed%
AGY_EMAIL=""
AGY_ASOF=""
fetch_antigravity() {
  local agy_bin
  agy_bin="${QUOTAPACE_AGY-$(command -v antigravity-usage)}"
  if [[ -z "$agy_bin" ]]; then
    # SwiftBar's PATH has no nvm shims; pick the newest nvm-installed copy.
    # shellcheck disable=SC2012
    agy_bin="$(ls -t "$HOME"/.nvm/versions/node/*/bin/antigravity-usage 2>/dev/null | head -1)"
  fi
  [[ -z "$agy_bin" || -z "$JQ_BIN" ]] && return 0

  local agy_cache="${CACHE_DIR}/antigravity.json" json
  json="$("$agy_bin" --json 2>/dev/null)"
  if [[ -n "$json" ]] && echo "$json" | "$JQ_BIN" -e '.models | length > 0' >/dev/null 2>&1; then
    mkdir -p "$CACHE_DIR" 2>/dev/null
    printf '%s\n' "$json" > "${agy_cache}.tmp" 2>/dev/null && mv -f "${agy_cache}.tmp" "$agy_cache" 2>/dev/null
  elif [[ -s "$agy_cache" ]]; then
    json="$(cat "$agy_cache")"
    AGY_ASOF="$(date -r "$agy_cache" "+%-d %b %H:%M")"
  else
    AGY_STATE="error"
    return 0
  fi

  AGY_STATE="ok"
  AGY_EMAIL="$(echo "$json" | "$JQ_BIN" -r '.email // empty' 2>/dev/null)"
  # Weekly rolling window: elapsed = share of the 7 days already gone.
  AGY_ROWS="$(echo "$json" | "$JQ_BIN" -r '
    .models
    | map(select(.isAutocompleteOnly | not))
    | [["Gemini", map(select(.modelId | startswith("gemini")))],
       ["Claude+GPT", map(select(.modelId | test("^(claude|gpt)")))]][]
    | select(.[1] | length > 0)
    | [.[0],
       ((1 - .[1][0].remainingPercentage) * 100),
       (.[1][0].resetTime | fromdate),
       ((604800000 - .[1][0].timeUntilResetMs) / 604800000 * 100
        | if . < 0 then 0 elif . > 100 then 100 else . end)]
    | @tsv' 2>/dev/null)"
}

print_antigravity_section() {
  [[ "$AGY_STATE" == "absent" ]] && return 0
  echo "---"
  echo "**Antigravity** | md=true size=13"
  if [[ "$AGY_STATE" == "error" ]]; then
    echo "Quota unavailable · try: antigravity-usage doctor | size=11 color=${ORANGE}"
    return 0
  fi

  local label used reset_epoch elapsed
  while IFS=$'\t' read -r label used reset_epoch elapsed; do
    [[ -z "$label" ]] && continue
    print_limit_line "$label" "$used" "$(pace_color "$used" "$elapsed")" "$elapsed"
    echo "Resets $(format_reset "$reset_epoch") | size=11 color=${SECONDARY_COLOR}"
  done <<< "$AGY_ROWS"

  local note="$AGY_EMAIL"
  [[ -n "$AGY_ASOF" ]] && note="${note:+${note} · }cached from ${AGY_ASOF}"
  [[ -n "$note" ]] && echo "${note} | size=11 color=${SECONDARY_COLOR}"
}

if [[ -z "$GH_BIN" || -z "$JQ_BIN" ]]; then
  MISSING=()
  [[ -z "$GH_BIN" ]] && MISSING+=("gh")
  [[ -z "$JQ_BIN" ]] && MISSING+=("jq")
  echo "?"
  echo "---"
  echo "QuotaPace | size=13"
  echo "Missing dependencies: ${MISSING[*]} | color=${RED} size=12"
  echo "brew install ${MISSING[*]} | font=Menlo size=11 color=${SECONDARY_COLOR}"
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# One-click recovery path instead of a dead-end error.
print_signin_menu() {
  local headline="$1"
  echo "? | sfimage=person.crop.circle.badge.exclamationmark sfcolor=#e74c3c"
  echo "---"
  echo "QuotaPace | size=13"
  echo "${headline} | color=${RED} size=12"
  echo "---"
  if [[ -x "$LOGIN_SCRIPT" ]]; then
    echo "Sign in with GitHub… | bash=${LOGIN_SCRIPT} color=${BLUE} size=12 sfimage=person.crop.circle.badge.plus"
    echo "Opens a one-time code in your browser | size=10 color=${SECONDARY_COLOR}"
  else
    # install.sh wasn't run, so the login helper isn't available — a dead
    # menu item would be worse than pointing at the terminal command.
    echo "Run in a terminal: | size=12"
    echo "gh auth login --web | font=Menlo size=11 color=${SECONDARY_COLOR}"
  fi
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
}

# `gh auth token` only reads local credentials; `gh auth status` hits the
# network, so it would misreport "not signed in" whenever the machine is offline.
if ! "$GH_BIN" auth token >/dev/null 2>&1; then
  print_signin_menu "Not signed in to GitHub"
  exit 0
fi

RESPONSE="$("$GH_BIN" api /copilot_internal/user 2>&1)"
API_EXIT=$?
OFFLINE_ASOF=""
if [[ $API_EXIT -ne 0 ]]; then
  if echo "$RESPONSE" | grep -q "HTTP 401"; then
    # The local token exists but GitHub rejected it — only here is re-login the fix.
    print_signin_menu "GitHub sign-in expired"
    exit 0
  elif echo "$RESPONSE" | grep -qE "HTTP (403|404)"; then
    # Signed in to GitHub, but this account/org has no Copilot access — sign-in
    # wouldn't fix this, so point at Copilot settings instead of a login action.
    echo "? | sfimage=exclamationmark.shield sfcolor=#e67e22"
    echo "---"
    echo "QuotaPace | size=13"
    echo "GitHub Copilot isn't enabled for this account | color=${ORANGE} size=12"
    echo "---"
    echo "Open Copilot settings | href=https://github.com/settings/copilot color=${BLUE} size=12 sfimage=gearshape"
    echo "---"
    echo "Refresh | refresh=true sfimage=arrow.clockwise"
    exit 0
  elif [[ -s "$CACHE_FILE" ]]; then
    # Network trouble (offline, DNS, GitHub down): render the last good
    # snapshot instead of an error; the cache mtime is when it was fetched.
    RESPONSE="$(cat "$CACHE_FILE")"
    OFFLINE_ASOF="$(date -r "$CACHE_FILE" "+%-d %b %H:%M")"
  else
    echo "? | sfimage=wifi.slash sfcolor=#e67e22"
    echo "---"
    echo "QuotaPace | size=13"
    echo "GitHub is unreachable and no cached data yet | color=${ORANGE} size=12"
    echo "$(sanitize_error "$RESPONSE") | font=Menlo size=10 color=${SECONDARY_COLOR}"
    echo "---"
    echo "Refresh | refresh=true sfimage=arrow.clockwise"
    exit 0
  fi
fi

# IFS must be a tab: fields like the org name can contain spaces, and default
# word splitting would shift every field after them.
IFS=$'\t' read -r LOGIN REMAINING ENTITLEMENT PERCENT_REMAINING OVERAGE_PERMITTED RESET_UTC PLAN ORG <<EOF
$(echo "$RESPONSE" | "$JQ_BIN" -r '
  [
    .login,
    .quota_snapshots.premium_interactions.quota_remaining,
    .quota_snapshots.premium_interactions.entitlement,
    .quota_snapshots.premium_interactions.percent_remaining,
    .quota_snapshots.premium_interactions.overage_permitted,
    .quota_reset_date_utc,
    .copilot_plan,
    (.organization_list[0].name // "personal")
  ] | @tsv')
EOF

if [[ -z "$PERCENT_REMAINING" || "$PERCENT_REMAINING" == "null" ]]; then
  echo "?"
  echo "---"
  echo "QuotaPace | size=13"
  echo "Unexpected response from Copilot API | color=${RED} size=12"
  echo "$(sanitize_error "$RESPONSE") | font=Menlo size=10 color=${SECONDARY_COLOR}"
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# Only a fresh, validated response refreshes the cache; atomic so a killed
# run can't leave a truncated file behind.
if [[ -z "$OFFLINE_ASOF" ]]; then
  mkdir -p "$CACHE_DIR" 2>/dev/null
  printf '%s\n' "$RESPONSE" > "${CACHE_FILE}.tmp" 2>/dev/null && mv -f "${CACHE_FILE}.tmp" "$CACHE_FILE" 2>/dev/null
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

PERCENT_TITLE="$(printf '%.0f' "$ACTUAL_USED_PCT")"
RESET_LOCAL="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$RESET_CLEAN" "+%b %d" 2>/dev/null)"
RESET_DISPLAY="$(format_reset "$EPOCH_END")"

# Menu bar color + status, based on pace (usage rate vs. time elapsed in the month)
COLOR="$GREEN"
STATUS="On pace"
if [[ -n "$ELAPSED_PCT" ]]; then
  COLOR="$(pace_color "$ACTUAL_USED_PCT" "$ELAPSED_PCT")"
  case "$(color_rank "$COLOR")" in
    3) STATUS="Burning fast — may run out before reset" ;;
    2) STATUS="Over pace" ;;
    1) STATUS="Slightly over pace" ;;
  esac
else
  if float_gt 20 "$PERCENT_REMAINING"; then
    COLOR="$RED"; STATUS="Low remaining"
  elif float_gt 50 "$PERCENT_REMAINING"; then
    COLOR="$YELLOW"; STATUS="Watch usage"
  fi
fi

# Header status covers every quota, not just Copilot: the worst pace across
# providers wins, and the offending quota is named in text so the alert
# doesn't rely on color alone.
fetch_antigravity
HEADER_COLOR="$COLOR"
HEADER_STATUS="$STATUS"
if [[ "$AGY_STATE" == "ok" ]]; then
  while IFS=$'\t' read -r AGY_LABEL AGY_USED _ AGY_ELAPSED; do
    [[ -z "$AGY_LABEL" ]] && continue
    AGY_COLOR="$(pace_color "$AGY_USED" "$AGY_ELAPSED")"
    if (( $(color_rank "$AGY_COLOR") > $(color_rank "$HEADER_COLOR") )); then
      HEADER_COLOR="$AGY_COLOR"
      case "$(color_rank "$AGY_COLOR")" in
        3) HEADER_STATUS="Antigravity ${AGY_LABEL} burning fast" ;;
        2) HEADER_STATUS="Antigravity ${AGY_LABEL} over pace" ;;
        1) HEADER_STATUS="Antigravity ${AGY_LABEL} slightly over pace" ;;
      esac
    fi
  done <<< "$AGY_ROWS"
  if [[ "$HEADER_COLOR" == "$GREEN" && "$HEADER_STATUS" == "On pace" ]]; then
    HEADER_STATUS="All quotas on pace"
  fi
fi

# Smaller than the native menu bar font size (14) — per user preference.
TITLE_PARAMS="size=12.5"
# Surface off-pace states in the menu bar itself via the alert color.
if [[ "$HEADER_COLOR" == "$RED" || "$HEADER_COLOR" == "$ORANGE" ]]; then
  TITLE_PARAMS+=" color=${HEADER_COLOR}"
fi
if [[ -n "$OFFLINE_ASOF" ]]; then
  TITLE_PARAMS+=" sfimage=wifi.slash"
fi
echo "${PERCENT_TITLE}% | ${TITLE_PARAMS}"
echo "---"
echo "QuotaPace | size=13"
echo "● ${HEADER_STATUS} | color=${HEADER_COLOR} size=11"
if [[ -n "$OFFLINE_ASOF" ]]; then
  echo "Offline · cached data from ${OFFLINE_ASOF} | size=11 color=${SECONDARY_COLOR}"
fi
echo "---"
# Usage-style bar: fill = quota used, tick = share of the billing month
# already elapsed. Fill past the tick means burning faster than time passes.
# Tick is skipped when the billing period couldn't be derived.
echo "**Copilot** | md=true size=13"
print_limit_line "Monthly" "$ACTUAL_USED_PCT" "$COLOR" "$ELAPSED_PCT"
echo "Resets ${RESET_DISPLAY:-${RESET_LOCAL:-$RESET_UTC}} · $(printf '%.0f' "$REMAINING") of ${ENTITLEMENT} left | size=11 color=${SECONDARY_COLOR}"
echo "${LOGIN} · ${PLAN} (${ORG}) | size=11 color=${SECONDARY_COLOR}"
print_antigravity_section
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
echo "Open Copilot settings | href=https://github.com/settings/copilot sfimage=gearshape"
