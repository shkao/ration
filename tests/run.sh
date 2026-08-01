#!/bin/bash
# Integration tests for ration.5m.sh.
#
# Each test runs the real plugin end to end against stub `gh` /
# `antigravity-usage` binaries and an isolated $HOME, then asserts on the
# rendered SwiftBar output. Requires macOS (the plugin uses BSD `date`) and
# a real `jq` on PATH.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/ration.5m.sh"
JQ="$(command -v jq)"

if [[ -z "$JQ" ]]; then
  echo "SKIP: jq is required to run the tests" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
CURRENT_TEST=""
OUTPUT=""

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# Fresh isolated HOME per test so caches and helper scripts never leak
# between cases (or from the developer's real account).
new_home() {
  FAKE_HOME="$TMP/home-$RANDOM"
  mkdir -p "$FAKE_HOME"
}

# Write a stub `gh`. $1 is the body handling `gh api ...`; `gh auth token`
# succeeds unless AUTH_EXIT is exported as nonzero.
make_gh() {
  GH_STUB="$TMP/gh-$RANDOM"
  cat > "$GH_STUB" <<EOF
#!/bin/bash
if [[ "\$1" == "auth" ]]; then exit "\${AUTH_EXIT:-0}"; fi
$1
EOF
  chmod +x "$GH_STUB"
}

make_agy() {
  AGY_STUB="$TMP/agy-$RANDOM"
  printf '#!/bin/bash\n%s\n' "$1" > "$AGY_STUB"
  chmod +x "$AGY_STUB"
}

make_counting_jq() {
  JQ_STUB="$TMP/jq-$RANDOM"
  printf '#!/bin/bash\nprintf x >> "%s/jq-calls"\nexec "%s" "$@"\n' \
    "$FAKE_HOME" "$JQ" > "$JQ_STUB"
  chmod +x "$JQ_STUB"
}

# The two most common stub setups, factored from repeated call sites.
make_gh_ok() {
  make_gh "echo '$(copilot_json "${1:-75}" "${2:-750}")'; exit 0"
}

make_agy_json() {
  make_agy "cat <<'JSON'
$(agy_json)
JSON"
}

# Run the plugin with the seams pointed at the stubs. Extra VAR=value
# arguments go last so they override the defaults (`env` lets the final
# assignment win).
run_plugin() {
  OUTPUT="$(env \
    HOME="$FAKE_HOME" \
    RATION_GH="${GH_STUB:-}" \
    RATION_JQ="$JQ" \
    RATION_AGY="${AGY_STUB:-}" \
    "$@" \
    "$PLUGIN" 2>/dev/null)"
}

begin() {
  CURRENT_TEST="$1"
  GH_STUB=""
  AGY_STUB=""
  new_home
}

expect_contains() {
  if grep -qF -- "$1" <<< "$OUTPUT"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${CURRENT_TEST}: output does not contain: $1" >&2
    echo "--- output ---" >&2
    echo "$OUTPUT" >&2
    echo "--------------" >&2
  fi
}

expect_not_contains() {
  if grep -qF -- "$1" <<< "$OUTPUT"; then
    FAIL=$((FAIL + 1))
    echo "FAIL: ${CURRENT_TEST}: output unexpectedly contains: $1" >&2
  else
    PASS=$((PASS + 1))
  fi
}

expect_check() {
  local description="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: ${CURRENT_TEST}: ${description}" >&2
  fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Copilot API response. Reset is ~15 days out so the elapsed share of the
# month sits near 50% regardless of when the tests run, which keeps the
# pace status deterministic: 25% used is always "On pace", 90% used is
# always "Burning fast".
copilot_json() {
  local percent_remaining="$1" remaining="$2"
  local reset
  reset="$(date -u -v+15d "+%Y-%m-%dT%H:%M:%S.000Z")"
  cat <<EOF
{
  "login": "octocat",
  "copilot_plan": "business",
  "organization_list": [{"name": "Acme Corp"}],
  "quota_reset_date_utc": "${reset}",
  "quota_snapshots": {
    "premium_interactions": {
      "quota_remaining": ${remaining},
      "entitlement": 1000,
      "percent_remaining": ${percent_remaining}
    }
  }
}
EOF
}

# Antigravity CLI response. timeUntilResetMs drives the pace tick, so the
# values below are fully deterministic: Gemini is 60% used at 50% of the
# week (slightly over pace), Claude+GPT is untouched with a fresh window.
agy_json() {
  cat <<'EOF'
{
  "email": "octocat@example.com",
  "models": [
    {"label": "Gemini 3 Flash", "modelId": "gemini-3-flash",
     "remainingPercentage": 0.40, "resetTime": "2026-07-15T12:00:00Z",
     "timeUntilResetMs": 302400000, "isAutocompleteOnly": false},
    {"label": "Claude Opus", "modelId": "claude-opus-4-6-thinking",
     "remainingPercentage": 1.0, "resetTime": "2026-07-20T12:00:00Z",
     "timeUntilResetMs": 604800000, "isAutocompleteOnly": false}
  ]
}
EOF
}

agy_exhausted_json() {
  agy_json | sed 's/"remainingPercentage": 0.40/"remainingPercentage": 0.0/'
}

codex_jsonl() {
  local five_hour_reset weekly_reset
  five_hour_reset="$(( $(date +%s) + 9000 ))"
  weekly_reset="$(( $(date +%s) + 302400 ))"
  cat <<EOF
{"timestamp":"2026-08-01T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":{"used_percent":60.0,"window_minutes":300,"resets_at":${five_hour_reset}},"secondary":{"used_percent":25.0,"window_minutes":10080,"resets_at":${weekly_reset}},"plan_type":"plus"}}}
EOF
}

seed_codex_snapshot() {
  mkdir -p "$FAKE_HOME/.codex/sessions/2026/08/01"
  codex_jsonl > "$FAKE_HOME/.codex/sessions/2026/08/01/rollout-test.jsonl"
}

seed_codex_weekly_only_snapshot() {
  local weekly_reset
  weekly_reset="$(( $(date +%s) + 302400 ))"
  mkdir -p "$FAKE_HOME/.codex/sessions/2026/08/01"
  printf '%s\n' \
    "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":2.0,\"window_minutes\":10080,\"resets_at\":${weekly_reset}},\"secondary\":null,\"plan_type\":\"plus\"}}}" \
    > "$FAKE_HOME/.codex/sessions/2026/08/01/rollout-test.jsonl"
}

seed_codex_snapshot_without_plan() {
  local weekly_reset
  weekly_reset="$(( $(date +%s) + 302400 ))"
  mkdir -p "$FAKE_HOME/.codex/sessions/2026/08/01"
  printf '%s\n' \
    "{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"limit_id\":\"codex\",\"primary\":{\"used_percent\":2.0,\"window_minutes\":10080,\"resets_at\":${weekly_reset}},\"secondary\":null}}}" \
    > "$FAKE_HOME/.codex/sessions/2026/08/01/rollout-test.jsonl"
}

seed_copilot_cache() {
  mkdir -p "$FAKE_HOME/Library/Caches/ration"
  copilot_json 75 750 > "$FAKE_HOME/Library/Caches/ration/quota.json"
}

seed_agy_cache() {
  mkdir -p "$FAKE_HOME/Library/Caches/ration"
  agy_json > "$FAKE_HOME/Library/Caches/ration/antigravity.json"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

begin "happy path renders usage, pace, and account"
make_gh_ok
run_plugin
expect_contains "25% | size=12.5"
expect_contains "● On pace"
expect_contains "25% used"
expect_contains "750 of 1000 left"
expect_contains "octocat · business (Acme Corp)"
# Menu bar identity: gauge glyph plus a tooltip naming the app and status.
expect_contains "sfimage=gauge"
expect_contains 'tooltip="Ration · 25% used · On pace"'
expect_contains 'tooltip="Tick = your fair share spent by now. Fill past it = borrowing from tomorrow."'
expect_not_contains "Antigravity"

begin "heavy usage escalates to burning fast"
make_gh_ok 10 100
run_plugin
expect_contains "● Burning through the ration · may run out before reset"
expect_contains "90% used"
# Off-pace states must surface in the menu bar itself via the alert color,
# and the red state must also swap the glyph so it doesn't rely on color alone.
expect_contains "90% | size=12.5 color="
expect_contains "sfimage=exclamationmark.triangle"

begin "exhausted quota counts down to reset day"
make_gh_ok 0 0
run_plugin
expect_contains "● Ration exhausted · see you on reset day"
expect_contains "100% used"
expect_contains "sfimage=exclamationmark.triangle"

begin "happy path writes the offline cache"
make_gh_ok
run_plugin
if [[ -s "$FAKE_HOME/Library/Caches/ration/quota.json" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL: ${CURRENT_TEST}: cache file missing" >&2
fi

begin "network failure falls back to cached data"
seed_copilot_cache
make_gh "echo 'error connecting to api.github.com: no such host'; exit 1"
run_plugin
expect_contains "sfimage=wifi.slash"
expect_contains "Offline · cached data from"
expect_contains "25% used"

begin "network failure without cache explains itself"
make_gh "echo 'error connecting to api.github.com: no such host'; exit 1"
run_plugin
expect_contains "GitHub is unreachable and no cached data yet"
expect_not_contains "Sign in with GitHub"

# RATION_TIMEOUT=1 shrinks the watchdog so these stay fast; the stubs
# sleep past it to simulate a stalled network call.
begin "hung gh call times out instead of hanging the refresh"
make_gh "sleep 2; echo 'never arrives'; exit 0"
run_plugin RATION_TIMEOUT=1
expect_contains "GitHub is unreachable and no cached data yet"
expect_contains "gh api gave no response within 1s"

begin "hung gh call falls back to cached data"
seed_copilot_cache
make_gh "sleep 2; echo 'never arrives'; exit 0"
run_plugin RATION_TIMEOUT=1
expect_contains "Offline · cached data from"
expect_contains "25% used"

begin "hung antigravity CLI times out and degrades to one line"
make_gh_ok
make_agy "sleep 2; exit 0"
run_plugin RATION_TIMEOUT=1
expect_contains "Quota unavailable · try: antigravity-usage doctor"

begin "Copilot and Antigravity fetch concurrently"
make_gh "touch '$FAKE_HOME/gh-started'
for _ in {1..40}; do
  if [[ -e '$FAKE_HOME/agy-started' ]]; then echo '$(copilot_json 75 750)'; exit 0; fi
  sleep 0.05
done
exit 1"
make_agy "touch '$FAKE_HOME/agy-started'
for _ in {1..40}; do
  if [[ -e '$FAKE_HOME/gh-started' ]]; then echo '$(agy_json)'; exit 0; fi
  sleep 0.05
done
exit 1"
run_plugin RATION_TIMEOUT=1
expect_contains "**Copilot**"
expect_contains "750 of 1000 left"
expect_contains "**Antigravity**"

begin "HTTP 401 asks to sign in again"
make_gh "echo 'HTTP 401: Bad credentials'; exit 1"
run_plugin
expect_contains "GitHub sign-in expired"

begin "HTTP 403 points at Copilot settings, not login"
make_gh "echo 'HTTP 403: forbidden'; exit 1"
run_plugin
expect_contains "GitHub Copilot isn't enabled for this account"
expect_not_contains "sign-in expired"

begin "signed out with no history shows first-run guidance"
make_gh "exit 0"
run_plugin AUTH_EXIT=1
expect_contains "Nothing to ration yet · no AI quota sources detected"
expect_contains "gh auth login"
expect_contains "antigravity-usage login"

begin "signed out with a cache still prompts to sign back in"
make_gh "exit 0"
seed_copilot_cache
run_plugin AUTH_EXIT=1
expect_contains "Not signed in to GitHub"

begin "nothing installed shows first-run guidance"
GH_STUB=""
run_plugin
expect_contains "Nothing to ration yet · no AI quota sources detected"

begin "missing jq names the fix"
GH_STUB=""
run_plugin RATION_JQ=
expect_contains "Missing dependencies: jq"
expect_contains "brew install jq"

begin "antigravity section renders groups with pace ticks"
make_gh_ok
make_agy_json
run_plugin
expect_contains "**Antigravity**"
# 60% used, tick at 50% of the week: fill 10 of 16 cells, tick at cell 8.
expect_contains "Gemini:     [████████│█░░░░░░]  60% used"
expect_contains "Claude+GPT: [│░░░░░░░░░░░░░░░]   0% used"
expect_contains "octocat@example.com"
# Gemini at +10 over pace must escalate the header past Copilot's green.
expect_contains "● Antigravity Gemini slightly over pace"
# The title shows the busiest quota across providers, not always Copilot.
expect_contains "60% | size=12.5"

begin "exhausted Antigravity quota reports the countdown state"
GH_STUB=""
make_agy "echo '$(agy_exhausted_json)'"
run_plugin
expect_contains "● Antigravity Gemini exhausted · see you on reset day"
expect_contains "sfimage=exclamationmark.triangle"

begin "antigravity CLI failure falls back to its cache"
make_gh_ok
make_agy "exit 1"
seed_agy_cache
run_plugin
expect_contains "octocat@example.com · cached from"

begin "antigravity CLI failure without cache degrades to one line"
make_gh_ok
make_agy "exit 1"
run_plugin
expect_contains "Quota unavailable · try: antigravity-usage doctor"

begin "antigravity alone works without gh installed"
GH_STUB=""
make_agy_json
run_plugin
# Title falls back to the busiest Antigravity group.
expect_contains "60% | size=12.5"
expect_contains "**Antigravity**"
expect_not_contains "**Copilot**"
expect_not_contains "Open Copilot settings"

begin "codex section renders local five-hour and weekly limits"
GH_STUB=""
seed_codex_snapshot
run_plugin
expect_contains "**Codex**"
expect_contains "5 hours:    [████████│█░░░░░░]  60% used"
expect_contains "Weekly:     [████░░░░│░░░░░░░]  25% used"
expect_contains "ChatGPT Plus · local Codex snapshot"
expect_contains "● Codex 5 hours slightly over pace"

begin "codex alone works without other providers"
GH_STUB=""
seed_codex_snapshot
run_plugin
expect_contains "60% | size=12.5"
expect_contains "**Codex**"
expect_not_contains "**Copilot**"
expect_not_contains "**Antigravity**"

begin "codex labels a primary weekly-only limit from its duration"
GH_STUB=""
seed_codex_weekly_only_snapshot
run_plugin
expect_contains "Weekly:"
expect_not_contains "5 hours:"

begin "codex snapshot without a plan keeps its quota fields aligned"
GH_STUB=""
seed_codex_snapshot_without_plan
run_plugin
expect_contains "Weekly:"
expect_contains "  2% used"
expect_contains "ChatGPT · local Codex snapshot"

begin "unchanged Codex snapshot reuses its parsed cache"
GH_STUB=""
seed_codex_snapshot
make_counting_jq
run_plugin RATION_JQ="$JQ_STUB"
run_plugin RATION_JQ="$JQ_STUB"
expect_check "unchanged snapshot was parsed more than once" test "$(wc -c < "$FAKE_HOME/jq-calls")" -eq 1
codex_jsonl >> "$FAKE_HOME/.codex/sessions/2026/08/01/rollout-test.jsonl"
run_plugin RATION_JQ="$JQ_STUB"
expect_check "changed snapshot did not invalidate the parsed cache" test "$(wc -c < "$FAKE_HOME/jq-calls")" -eq 2

begin "unchanged Codex history without limits reuses its empty cache"
GH_STUB=""
mkdir -p "$FAKE_HOME/.codex/sessions/2026/08/01"
printf '%s\n' '{"type":"session_meta"}' \
  > "$FAKE_HOME/.codex/sessions/2026/08/01/rollout-test.jsonl"
make_counting_jq
run_plugin RATION_JQ="$JQ_STUB"
run_plugin RATION_JQ="$JQ_STUB"
expect_check "empty Codex result was parsed more than once" test "$(wc -c < "$FAKE_HOME/jq-calls")" -eq 1

begin "antigravity can set the title above a quieter codex quota"
GH_STUB=""
seed_codex_weekly_only_snapshot
make_agy_json
run_plugin
expect_contains "60% | size=12.5"

begin "no Copilot seat hides the section when Antigravity has data"
make_gh "echo 'HTTP 403: forbidden'; exit 1"
make_agy_json
run_plugin
expect_contains "**Antigravity**"
expect_not_contains "**Copilot**"
expect_not_contains "isn't enabled"

begin "expired sign-in shrinks to a section line when Antigravity has data"
make_gh "echo 'HTTP 401: Bad credentials'; exit 1"
make_agy_json
run_plugin
expect_contains "**Copilot**"
expect_contains "GitHub sign-in expired"
expect_contains "**Antigravity**"

begin "installer reproduces an isolated per-user setup"
PLUGIN_DIR="$FAKE_HOME/custom swiftbar plugins"
mkdir -p "$PLUGIN_DIR" "$FAKE_HOME/.quotapace-helpers"
touch "$PLUGIN_DIR/quotapace.5m.sh" "$FAKE_HOME/.quotapace-helpers/legacy"
OUTPUT="$(cd /private/tmp && HOME="$FAKE_HOME" SWIFTBAR_PLUGIN_DIR="$PLUGIN_DIR" "$ROOT/install.sh")"
expect_contains "Plugin: $PLUGIN_DIR/ration.5m.sh"
expect_check "installed plugin is executable" test -x "$PLUGIN_DIR/ration.5m.sh"
expect_check "installed helper is executable" test -x "$FAKE_HOME/.ration-helpers/ration-login.sh"
expect_check "installed plugin matches the checkout" cmp -s "$PLUGIN" "$PLUGIN_DIR/ration.5m.sh"
expect_check "installed helper matches the checkout" cmp -s \
  "$ROOT/helpers/ration-login.sh" "$FAKE_HOME/.ration-helpers/ration-login.sh"
expect_check "legacy plugin was removed" test ! -e "$PLUGIN_DIR/quotapace.5m.sh"
expect_check "legacy helper directory was removed" test ! -e "$FAKE_HOME/.quotapace-helpers"

# ---------------------------------------------------------------------------

echo
echo "passed ${PASS}, failed ${FAIL}"
[[ $FAIL -eq 0 ]]
