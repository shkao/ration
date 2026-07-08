#!/bin/bash
# <xbar.title>QuotaPace</xbar.title>
# <xbar.version>v2.5</xbar.version>
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
# One jq pass over a snapshot: email on the first line, then one TSV row per
# quota group. Empty output means the payload isn't a usable snapshot.
# Weekly rolling window: elapsed = share of the 7 days already gone.
parse_antigravity() {
  "$JQ_BIN" -r '
    select((.models | length) > 0)
    | (.email // ""),
      (.models
       | map(select(.isAutocompleteOnly | not))
       | [["Gemini", map(select(.modelId | startswith("gemini")))],
          ["Claude+GPT", map(select(.modelId | test("^(claude|gpt)")))]][]
       | select(.[1] | length > 0)
       | [.[0],
          ((1 - .[1][0].remainingPercentage) * 100),
          (.[1][0].resetTime | fromdate),
          ((604800000 - .[1][0].timeUntilResetMs) / 604800000 * 100
           | if . < 0 then 0 elif . > 100 then 100 else . end)]
       | @tsv)' 2>/dev/null
}

fetch_antigravity() {
  local agy_bin
  agy_bin="${QUOTAPACE_AGY-$(command -v antigravity-usage)}"
  if [[ -z "$agy_bin" ]]; then
    # SwiftBar's PATH has no nvm shims; pick the newest nvm-installed copy.
    # shellcheck disable=SC2012
    agy_bin="$(ls -t "$HOME"/.nvm/versions/node/*/bin/antigravity-usage 2>/dev/null | head -1)"
  fi
  [[ -z "$agy_bin" ]] && return 0

  local agy_cache="${CACHE_DIR}/antigravity.json" json parsed=""
  json="$("$agy_bin" --json 2>/dev/null)"
  [[ -n "$json" ]] && parsed="$(parse_antigravity <<< "$json")"
  if [[ -n "$parsed" ]]; then
    mkdir -p "$CACHE_DIR" 2>/dev/null
    printf '%s\n' "$json" > "${agy_cache}.tmp" 2>/dev/null && mv -f "${agy_cache}.tmp" "$agy_cache" 2>/dev/null
  elif [[ -s "$agy_cache" ]]; then
    parsed="$(parse_antigravity < "$agy_cache")"
    if [[ -z "$parsed" ]]; then
      AGY_STATE="error"
      return 0
    fi
    AGY_ASOF="$(date -r "$agy_cache" "+%-d %b %H:%M")"
  else
    AGY_STATE="error"
    return 0
  fi

  AGY_STATE="ok"
  AGY_EMAIL="${parsed%%$'\n'*}"
  AGY_ROWS=""
  [[ "$parsed" == *$'\n'* ]] && AGY_ROWS="${parsed#*$'\n'}"
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

# Shared chrome for full-menu (takeover) screens: menu bar glyph, app header,
# headline, optional extra lines, refresh action. Callers pass complete
# SwiftBar lines; this owns only the skeleton around them.
print_takeover_menu() {
  local title="$1" headline="$2"
  shift 2
  echo "$title"
  echo "---"
  echo "QuotaPace | size=13"
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

# jq parses every provider's output, so it stays a hard requirement. gh is
# only needed for Copilot; its absence just means that provider isn't shown.
if [[ -z "$JQ_BIN" ]]; then
  print_takeover_menu "?" \
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
  print_takeover_menu "? | sfimage=person.crop.circle.badge.exclamationmark sfcolor=#e74c3c" \
    "${headline} | color=${RED} size=12" "${extras[@]}"
}

# GitHub Copilot quota via `gh api`. Detection rule: the provider counts as
# "in use" when gh is installed and signed in, or when a previous run left a
# cache (so a signed-out Copilot user gets a re-login prompt instead of a
# silently vanished section). No gh, no token, no cache: no Copilot section.
CP_STATE="absent" # absent | ok | offline | signedout | expired | nocopilot | unreachable | badresponse
CP_ERR=""
OFFLINE_ASOF=""
# Single home for state copy rendered both as a section line and a takeover menu.
CP_MSG_UNREACHABLE="GitHub is unreachable and no cached data yet"
CP_MSG_BADRESPONSE="Unexpected response from Copilot API"
fetch_copilot() {
  [[ -z "$GH_BIN" ]] && return 0

  # `gh auth token` only reads local credentials; `gh auth status` hits the
  # network, so it would misreport "not signed in" whenever the machine is offline.
  if ! "$GH_BIN" auth token >/dev/null 2>&1; then
    [[ -s "$CACHE_FILE" ]] && CP_STATE="signedout"
    return 0
  fi

  RESPONSE="$("$GH_BIN" api /copilot_internal/user 2>&1)"
  local api_exit=$?
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
      OFFLINE_ASOF="$(date -r "$CACHE_FILE" "+%-d %b %H:%M")"
      CP_STATE="offline"
    else
      CP_STATE="unreachable"
      CP_ERR="$(sanitize_error "$RESPONSE")"
      return 0
    fi
  else
    CP_STATE="ok"
  fi
}

# Parse the (fresh or cached) response and derive pace. Sets CP_STATE to
# badresponse when the payload doesn't look like a Copilot quota snapshot.
compute_copilot() {
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
# format_reset always yields text ("unknown" when the epoch is unparsable).
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
}

cp_has_data() { [[ "$CP_STATE" == "ok" || "$CP_STATE" == "offline" ]]; }

print_copilot_section() {
  case "$CP_STATE" in absent | nocopilot) return 0 ;; esac
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

# First-run guidance when no provider is detected at all.
print_welcome_menu() {
  local copilot_hint="brew install gh && gh auth login --web | font=Menlo size=11 color=${SECONDARY_COLOR}"
  [[ -n "$GH_BIN" && -x "$LOGIN_SCRIPT" ]] && copilot_hint="$(signin_item)"
  print_takeover_menu "? | size=12.5" \
    "No AI quota sources detected | color=${ORANGE} size=12" \
    "---" \
    "For GitHub Copilot: | size=12" \
    "$copilot_hint" \
    "For Antigravity: | size=12" \
    "npm install -g antigravity-usage && antigravity-usage login | font=Menlo size=11 color=${SECONDARY_COLOR}"
}

fetch_copilot
if cp_has_data; then
  compute_copilot
fi
fetch_antigravity

# When Copilot is in a problem state and no other provider has data, keep the
# dedicated full-menu treatment: it is unambiguous and actionable. With
# Antigravity data present, the same states shrink to lines inside the
# Copilot section so the working provider stays visible.
if [[ "$AGY_STATE" != "ok" ]]; then
  case "$CP_STATE" in
    signedout)
      print_signin_menu "Not signed in to GitHub"
      exit 0
      ;;
    expired)
      print_signin_menu "GitHub sign-in expired"
      exit 0
      ;;
    nocopilot)
      # Sign-in wouldn't fix a missing seat, so point at Copilot settings.
      print_takeover_menu "? | sfimage=exclamationmark.shield sfcolor=#e67e22" \
        "GitHub Copilot isn't enabled for this account | color=${ORANGE} size=12" \
        "---" \
        "Open Copilot settings | href=https://github.com/settings/copilot color=${BLUE} size=12 sfimage=gearshape"
      exit 0
      ;;
    unreachable)
      print_takeover_menu "? | sfimage=wifi.slash sfcolor=#e67e22" \
        "${CP_MSG_UNREACHABLE} | color=${ORANGE} size=12" \
        "${CP_ERR} | font=Menlo size=10 color=${SECONDARY_COLOR}"
      exit 0
      ;;
    badresponse)
      print_takeover_menu "?" \
        "${CP_MSG_BADRESPONSE} | color=${RED} size=12" \
        "${CP_ERR} | font=Menlo size=10 color=${SECONDARY_COLOR}"
      exit 0
      ;;
    absent)
      if [[ "$AGY_STATE" == "absent" ]]; then
        print_welcome_menu
        exit 0
      fi
      ;;
  esac
fi

# Header status covers every quota with data: the worst pace across providers
# wins, and the offending quota is named in text so the alert doesn't rely on
# color alone.
HEADER_COLOR="$GREEN"
HEADER_STATUS="On pace"
if cp_has_data; then
  HEADER_COLOR="$COLOR"
  HEADER_STATUS="$STATUS"
fi
if [[ "$AGY_STATE" == "ok" ]]; then
  while IFS=$'\t' read -r AGY_LABEL AGY_USED _ AGY_ELAPSED; do
    [[ -z "$AGY_LABEL" ]] && continue
    AGY_COLOR="$(pace_color "$AGY_USED" "$AGY_ELAPSED")"
    AGY_RANK="$(color_rank "$AGY_COLOR")"
    if (( AGY_RANK > $(color_rank "$HEADER_COLOR") )); then
      HEADER_COLOR="$AGY_COLOR"
      case "$AGY_RANK" in
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

if ! cp_has_data && [[ "$AGY_STATE" != "ok" ]]; then
  # Reachable only when Copilot is absent and the Antigravity CLI errored.
  HEADER_COLOR="$ORANGE"
  HEADER_STATUS="No quota data"
fi

# Menu bar percent: Copilot when it has data, else the busiest Antigravity group.
if ! cp_has_data; then
  PERCENT_TITLE=""
  if [[ "$AGY_STATE" == "ok" ]]; then
    PERCENT_TITLE="$(awk -F'\t' '$2 > m { m = $2 } END { printf "%.0f", m }' <<< "$AGY_ROWS")"
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
if [[ -n "$PERCENT_TITLE" ]]; then
  echo "${PERCENT_TITLE}% | ${TITLE_PARAMS}"
else
  echo "? | ${TITLE_PARAMS}"
fi
echo "---"
echo "QuotaPace | size=13"
echo "● ${HEADER_STATUS} | color=${HEADER_COLOR} size=11"
if [[ -n "$OFFLINE_ASOF" ]]; then
  echo "Offline · cached data from ${OFFLINE_ASOF} | size=11 color=${SECONDARY_COLOR}"
fi
print_copilot_section
print_antigravity_section
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
if [[ "$CP_STATE" != "absent" ]]; then
  echo "Open Copilot settings | href=https://github.com/settings/copilot sfimage=gearshape"
fi
