#!/bin/bash
# <xbar.title>Ration</xbar.title>
# <xbar.version>v3.1</xbar.version>
# <xbar.author>Allen Kao</xbar.author>
# <xbar.author.github>shkao</xbar.author.github>
# <xbar.desc>Rations your AI quotas: tracks Copilot, Codex, and Antigravity pace so they last until reset</xbar.desc>
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
LOGIN_SCRIPT="${HOME}/.ration-helpers/ration-login.sh"
BAR_WIDTH=16
PROVIDERS=("copilot" "codex" "antigravity")

# Last successful API response, so going offline shows stale data instead of errors.
CACHE_DIR="${HOME}/Library/Caches/ration"
CACHE_FILE="${CACHE_DIR}/quota.json"
CODEX_HOME="${HOME}/.codex"
CODEX_CACHE_FILE="${CACHE_DIR}/codex.tsv"

# Provider contract: <id>_{fetch,export,postprocess,has_data,rows,
# update_header,render,takeover,settings,present,welcome}. Main orchestration
# dispatches only through these hooks; source-specific behavior stays private.
provider_call() {
  local provider="$1" hook="$2"
  shift 2
  "${provider}_${hook}" "$@"
}

provider_any_data() {
  local provider
  for provider in "${PROVIDERS[@]}"; do
    provider_call "$provider" has_data && return 0
  done
  return 1
}

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

# macOS has no `timeout`; without one a stalled network call would hang the
# SwiftBar refresh indefinitely. The watchdog's output goes to /dev/null so
# its sleep can't hold a caller's command-substitution pipe open. `:-` so an
# empty override still means the default; tests shorten it via RATION_TIMEOUT.
FETCH_TIMEOUT="${RATION_TIMEOUT:-15}"
run_with_timeout() {
  "$@" &
  local cmd=$!
  ( sleep "$FETCH_TIMEOUT" && kill "$cmd" ) >/dev/null 2>&1 &
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
  json="$(run_with_timeout "$agy_bin" --json 2>/dev/null)"
  [[ -n "$json" ]] && parsed="$(parse_antigravity <<< "$json")"
  if [[ -n "$parsed" ]]; then
    write_cache "$agy_cache" "$json"
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

antigravity_export() {
  declare -p AGY_STATE AGY_ROWS AGY_EMAIL AGY_ASOF
}

antigravity_postprocess() { :; }
antigravity_has_data() { [[ "$AGY_STATE" == "ok" ]]; }
antigravity_rows() { antigravity_has_data && printf '%s\n' "$AGY_ROWS"; }
antigravity_update_header() {
  antigravity_has_data && update_header_from_rows "Antigravity" "$AGY_ROWS"
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
codex_candidate_files() {
  local -a session_days=("$CODEX_HOME"/sessions/*/*/*)
  local -a files
  local day file
  local day_count=0 file_count=0
  local i j

  # Session paths contain sortable YYYY/MM/DD and rollout timestamps. Inspect
  # at most 20 sessions from each of the newest three active days.
  for ((i = ${#session_days[@]} - 1; i >= 0 && day_count < 3; i--)); do
    day="${session_days[$i]}"
    [[ -d "$day" ]] || continue
    day_count=$((day_count + 1))
    files=("$day"/*.jsonl)
    file_count=0
    for ((j = ${#files[@]} - 1; j >= 0 && file_count < 20; j--)); do
      file="${files[$j]}"
      [[ -f "$file" ]] || continue
      printf '%s\n' "$file"
      file_count=$((file_count + 1))
    done
  done

  # Older Codex versions move sessions into one archive directory. The
  # timestamped filenames keep the newest 20 selectable without reading them.
  files=("$CODEX_HOME"/archived_sessions/*.jsonl)
  file_count=0
  for ((j = ${#files[@]} - 1; j >= 0 && file_count < 20; j--)); do
    file="${files[$j]}"
    [[ -f "$file" ]] || continue
    printf '%s\n' "$file"
    file_count=$((file_count + 1))
  done
}

codex_fetch() {
  local candidate_files signature cached_signature file parsed=""
  candidate_files="$(codex_candidate_files)"
  [[ -z "$candidate_files" ]] && return 0
  signature="$(while IFS= read -r file; do
    stat -f '%m:%z:%N' "$file" 2>/dev/null
  done <<< "$candidate_files" | cksum | awk '{ print $1 ":" $2 }')"

  if [[ -s "$CODEX_CACHE_FILE" ]]; then
    cached_signature="$(sed -n '1p' "$CODEX_CACHE_FILE")"
    if [[ "$cached_signature" == "$signature" ]]; then
      parsed="$(sed -n '2p' "$CODEX_CACHE_FILE")"
    fi
  fi

  if [[ "$cached_signature" != "$signature" ]]; then
    while IFS= read -r file; do
      parsed="$(tail -r "$file" 2>/dev/null | "$JQ_BIN" -r '
        select(.type == "event_msg" and .payload.type == "token_count")
        | .payload.rate_limits
        | select(.limit_id == "codex" and .primary.used_percent != null)
        | [(.plan_type // "__RATION_NO_PLAN__"),
           .primary.used_percent, .primary.window_minutes, .primary.resets_at,
           (.secondary.used_percent // ""), (.secondary.window_minutes // ""),
           (.secondary.resets_at // "")]
        | @tsv' 2>/dev/null | head -1)"
      [[ -n "$parsed" ]] && break
    done <<< "$candidate_files"
    write_cache "$CODEX_CACHE_FILE" "${signature}"$'\n'"${parsed}"
  fi
  [[ -z "$parsed" ]] && return 0

  local primary_used primary_window primary_reset secondary_used secondary_window secondary_reset
  IFS=$'\t' read -r CODEX_PLAN primary_used primary_window primary_reset \
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
    elapsed="$(awk -v now="$now" -v reset="$reset" -v minutes="$window" 'BEGIN {
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
  declare -p CODEX_STATE CODEX_ROWS CODEX_PLAN
}

codex_postprocess() { :; }
codex_has_data() { [[ "$CODEX_STATE" == "ok" ]]; }
codex_rows() { codex_has_data && printf '%s\n' "$CODEX_ROWS"; }
codex_update_header() {
  codex_has_data && update_header_from_rows "Codex" "$CODEX_ROWS"
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
  echo "${plan_display} · local Codex snapshot | size=11 color=${SECONDARY_COLOR}"
}

codex_takeover() { return 1; }
codex_settings() { :; }
codex_present() { [[ "$CODEX_STATE" != "absent" ]]; }
codex_welcome() {
  echo "For Codex (signed-in local app or CLI): | size=12"
  echo "Complete one response to create a usage snapshot | size=11 color=${SECONDARY_COLOR}"
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

  RESPONSE="$(run_with_timeout "$GH_BIN" api /copilot_internal/user 2>&1)"
  local api_exit=$?
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

copilot_export() {
  declare -p CP_STATE CP_ERR OFFLINE_ASOF RESPONSE
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

PERCENT_TITLE="$(printf '%.0f' "$ACTUAL_USED_PCT")"
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

# Header status covers every quota with data: the worst pace across providers
# wins, and the offending quota is named in text so the alert doesn't rely on
# color alone.
HEADER_COLOR="$GREEN"
HEADER_STATUS="On pace"
HEADER_ICON=""
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" update_header
done
if [[ "$HEADER_COLOR" == "$GREEN" && "$HEADER_STATUS" == "On pace" ]] && \
   provider_any_data_except "copilot"; then
  HEADER_STATUS="All rations on pace"
fi

if ! provider_any_data; then
  HEADER_COLOR="$ORANGE"
  HEADER_STATUS="No quota data"
fi

# Menu bar percent: the busiest quota across every provider with data.
PERCENT_TITLE="$({
  for provider in "${PROVIDERS[@]}"; do
    provider_call "$provider" has_data && provider_call "$provider" rows
  done
} | awk -F'\t' '$2 != "" && (!seen || $2 > max) { max = $2; seen = 1 }
  END { if (seen) printf "%.0f", max }')"

# Smaller than the native menu bar font size (14) — per user preference.
TITLE_PARAMS="size=12.5"
# Surface off-pace states in the menu bar itself via the alert color.
if [[ "$HEADER_COLOR" == "$RED" || "$HEADER_COLOR" == "$ORANGE" ]]; then
  TITLE_PARAMS+=" color=${HEADER_COLOR}"
fi
# Gauge glyph gives the bare percentage an identity next to other numeric
# menu bar items. Red swaps in a warning glyph so the worst state doesn't
# rely on color alone; offline keeps its wifi-slash.
TITLE_ICON="gauge"
[[ "$HEADER_COLOR" == "$RED" ]] && TITLE_ICON="exclamationmark.triangle"
[[ -n "$HEADER_ICON" ]] && TITLE_ICON="$HEADER_ICON"
TITLE_PARAMS+=" sfimage=${TITLE_ICON}"
TITLE_TOOLTIP="Ration · ${HEADER_STATUS}"
[[ -n "$PERCENT_TITLE" ]] && TITLE_TOOLTIP="Ration · ${PERCENT_TITLE}% used · ${HEADER_STATUS}"
TITLE_PARAMS+=" tooltip=\"${TITLE_TOOLTIP}\""
if [[ -n "$PERCENT_TITLE" ]]; then
  echo "${PERCENT_TITLE}% | ${TITLE_PARAMS}"
else
  echo "? | ${TITLE_PARAMS}"
fi
echo "---"
echo "Ration | size=13"
echo "● ${HEADER_STATUS} | color=${HEADER_COLOR} size=11"
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" render
done
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
for provider in "${PROVIDERS[@]}"; do
  provider_call "$provider" settings
done
