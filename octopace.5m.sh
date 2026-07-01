#!/bin/bash
# <xbar.title>Octopace</xbar.title>
# <xbar.version>v1.2</xbar.version>
# <xbar.author>Allen Kao</xbar.author>
# <xbar.author.github>shkao</xbar.author.github>
# <xbar.desc>Tracks GitHub Copilot premium request quota and Codex rate limits</xbar.desc>
# <xbar.dependencies>gh,jq,awk</xbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Consistent decimal points regardless of the user's locale
export LC_ALL=C

GH_BIN="$(command -v gh)"
JQ_BIN="$(command -v jq)"


# Adaptive "light_appearance,dark_appearance" colors — needed because any line
# using font= drops out of the native menu-item text color and defaults to a
# low-contrast color unless one is set explicitly.
PRIMARY_COLOR="#1c1c1e,#f5f5f7"
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
LOGIN_SCRIPT="${HOME}/.octopace-helpers/octopace-login.sh"
CODEX_SESSIONS_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
BAR_WIDTH=8

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

usage_bar() {
  local percent_left="$1"
  awk -v p="$percent_left" -v width="$BAR_WIDTH" 'BEGIN {
    filled = int((p * width / 100) + 0.5)
    if (filled < 0) filled = 0
    if (filled > width) filled = width
    bar = ""
    for (i = 0; i < filled; i++) bar = bar "█"
    for (i = filled; i < width; i++) bar = bar "░"
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
  local percent_left="$2"
  local reset_text="$3"
  local color="$4"
  local rounded bar
  rounded="$(printf '%.0f' "$percent_left")"
  bar="$(usage_bar "$rounded")"
  # %-8s fits the longest label ("Monthly:") so bars align across sections
  printf '%-8s [%s] %3s%% · %s | font=Menlo size=11 color=%s\n' \
    "${label}:" "$bar" "$rounded" "$reset_text" "$color"
}

# Codex has no billing-period start, so pace can't be computed — color by
# remaining quota instead, and only at genuinely low levels to avoid alarm
# noise from the fast-cycling 5h window.
codex_color() {
  local percent_left="$1"
  if float_gt 10 "$percent_left"; then
    echo "$RED"
  elif float_gt 20 "$percent_left"; then
    echo "$ORANGE"
  else
    echo "$PRIMARY_COLOR"
  fi
}

CODEX_STATUS="ok"
CODEX_PRIMARY_LEFT=""
CODEX_PRIMARY_RESET=""
CODEX_SECONDARY_LEFT=""
CODEX_SECONDARY_RESET=""
if [[ -z "$JQ_BIN" ]]; then
  CODEX_STATUS="jq not found on PATH"
elif [[ ! -d "$CODEX_SESSIONS_DIR" ]]; then
  CODEX_STATUS="Codex sessions directory not found"
else
  CODEX_LIMITS=""
  while IFS= read -r session_file; do
    CODEX_LIMITS="$($JQ_BIN -cr '
      select(.payload.rate_limits.primary.used_percent != null and .payload.rate_limits.secondary.used_percent != null) |
      [
        .payload.rate_limits.primary.used_percent,
        .payload.rate_limits.primary.resets_at,
        .payload.rate_limits.secondary.used_percent,
        .payload.rate_limits.secondary.resets_at
      ] | @tsv
    ' "$session_file" 2>/dev/null | tail -1)"
    if [[ -n "$CODEX_LIMITS" ]]; then
      break
    fi
  done < <(find "$CODEX_SESSIONS_DIR" -name '*.jsonl' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null)

  if [[ -n "$CODEX_LIMITS" ]]; then
    IFS=$'\t' read -r CODEX_PRIMARY_USED CODEX_PRIMARY_RESET CODEX_SECONDARY_USED CODEX_SECONDARY_RESET <<< "$CODEX_LIMITS"
    CODEX_PRIMARY_LEFT="$(awk -v used="$CODEX_PRIMARY_USED" 'BEGIN { printf "%.1f", 100 - used }')"
    CODEX_SECONDARY_LEFT="$(awk -v used="$CODEX_SECONDARY_USED" 'BEGIN { printf "%.1f", 100 - used }')"
  else
    CODEX_STATUS="Codex rate-limit snapshot not found"
  fi
fi

print_codex_usage() {
  echo "---"
  echo "**Codex** | md=true size=13"
  if [[ "$CODEX_STATUS" == "ok" ]]; then
    print_limit_line "5h" "$CODEX_PRIMARY_LEFT" "$(format_reset "$CODEX_PRIMARY_RESET")" "$(codex_color "$CODEX_PRIMARY_LEFT")"
    print_limit_line "Weekly" "$CODEX_SECONDARY_LEFT" "$(format_reset "$CODEX_SECONDARY_RESET")" "$(codex_color "$CODEX_SECONDARY_LEFT")"
  else
    echo "${CODEX_STATUS} | size=11 color=${ORANGE}"
  fi
}

if [[ -z "$GH_BIN" || -z "$JQ_BIN" ]]; then
  MISSING=()
  [[ -z "$GH_BIN" ]] && MISSING+=("gh")
  [[ -z "$JQ_BIN" ]] && MISSING+=("jq")
  echo "?"
  echo "---"
  echo "Octopace | size=13"
  echo "Missing dependencies: ${MISSING[*]} | color=${RED} size=12"
  echo "brew install ${MISSING[*]} | font=Menlo size=11 color=${SECONDARY_COLOR}"
  print_codex_usage
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
fi

# Not signed in to gh at all: give a one-click recovery path instead of a dead-end error.
if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "? | sfimage=person.crop.circle.badge.exclamationmark sfcolor=#e74c3c"
  echo "---"
  echo "Octopace | size=13"
  echo "Not signed in to GitHub | color=${RED} size=12"
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
  print_codex_usage
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
fi

RESPONSE="$("$GH_BIN" api /copilot_internal/user 2>&1)"
API_EXIT=$?
if [[ $API_EXIT -ne 0 ]]; then
  if echo "$RESPONSE" | grep -qE "HTTP (401|403|404)"; then
    # Signed in to GitHub, but this account/org has no Copilot access — sign-in
    # wouldn't fix this, so point at Copilot settings instead of a login action.
    echo "? | sfimage=exclamationmark.shield sfcolor=#e67e22"
    echo "---"
    echo "Octopace | size=13"
    echo "GitHub Copilot isn't enabled for this account | color=${ORANGE} size=12"
    echo "---"
    echo "Open Copilot settings | href=https://github.com/settings/copilot color=${BLUE} size=12 sfimage=gearshape"
  else
    echo "!"
    echo "---"
    echo "Octopace | size=13"
    echo "Failed to fetch Copilot quota | color=${RED} size=12"
    echo "$(sanitize_error "$RESPONSE") | font=Menlo size=10 color=${SECONDARY_COLOR}"
  fi
  print_codex_usage
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
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
  echo "Octopace | size=13"
  echo "Unexpected response from Copilot API | color=${RED} size=12"
  echo "$(sanitize_error "$RESPONSE") | font=Menlo size=10 color=${SECONDARY_COLOR}"
  print_codex_usage
  echo "---"
  echo "Refresh | refresh=true sfimage=arrow.clockwise"
  exit 0
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

PERCENT_TITLE="$(printf '%.0f' "$PERCENT_REMAINING")"
RESET_LOCAL="$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$RESET_CLEAN" "+%b %d" 2>/dev/null)"
RESET_DISPLAY="$(format_reset "$EPOCH_END")"

# Menu bar color + status, based on pace (usage rate vs. time elapsed in the month)
COLOR="$GREEN"
STATUS="On pace"
if [[ -n "$ELAPSED_PCT" ]]; then
  DIFF=$(awk -v used="$ACTUAL_USED_PCT" -v elapsed="$ELAPSED_PCT" 'BEGIN { printf "%.4f", used - elapsed }')
  if float_gt "$DIFF" 30; then
    COLOR="$RED"; STATUS="Burning fast — may run out before reset"
  elif float_gt "$DIFF" 15; then
    COLOR="$ORANGE"; STATUS="Over pace"
  elif float_gt "$DIFF" 5; then
    COLOR="$YELLOW"; STATUS="Slightly over pace"
  fi
else
  if float_gt 20 "$PERCENT_REMAINING"; then
    COLOR="$RED"; STATUS="Low remaining"
  elif float_gt 50 "$PERCENT_REMAINING"; then
    COLOR="$YELLOW"; STATUS="Watch usage"
  fi
fi

CODEX_TITLE="?"
if [[ "$CODEX_STATUS" == "ok" && -n "$CODEX_PRIMARY_LEFT" ]]; then
  CODEX_TITLE="$(printf '%.0f' "$CODEX_PRIMARY_LEFT")%"
fi

# Smaller than the native menu bar font size (14) — per user preference.
TITLE_PARAMS="size=12.5"
# Surface off-pace states in the menu bar itself via the alert color.
if [[ "$COLOR" == "$RED" || "$COLOR" == "$ORANGE" ]]; then
  TITLE_PARAMS+=" color=${COLOR}"
fi
echo "C ${PERCENT_TITLE}% · X ${CODEX_TITLE} | ${TITLE_PARAMS}"
echo "---"
echo "Octopace | size=13"
echo "● ${STATUS} | color=${COLOR} size=11"
echo "---"
echo "**Copilot** | md=true size=13"
print_limit_line "Monthly" "$PERCENT_REMAINING" "${RESET_DISPLAY:-${RESET_LOCAL:-$RESET_UTC}}" "$COLOR"
echo "$(printf '%.0f' "$REMAINING") of ${ENTITLEMENT} requests left | size=11 color=${SECONDARY_COLOR}"
print_codex_usage
echo "---"
echo "${LOGIN} · ${PLAN} (${ORG}) | size=11 color=${SECONDARY_COLOR}"
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
echo "Open Copilot settings | href=https://github.com/settings/copilot sfimage=gearshape"
