#!/bin/bash
# Integration tests for quotapace.5m.sh.
#
# Each test runs the real plugin end to end against stub `gh` /
# `antigravity-usage` binaries and an isolated $HOME, then asserts on the
# rendered SwiftBar output. Requires macOS (the plugin uses BSD `date`) and
# a real `jq` on PATH.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/quotapace.5m.sh"
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
    QUOTAPACE_GH="${GH_STUB:-}" \
    QUOTAPACE_JQ="$JQ" \
    QUOTAPACE_AGY="${AGY_STUB:-}" \
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

seed_copilot_cache() {
  mkdir -p "$FAKE_HOME/Library/Caches/quotapace"
  copilot_json 75 750 > "$FAKE_HOME/Library/Caches/quotapace/quota.json"
}

seed_agy_cache() {
  mkdir -p "$FAKE_HOME/Library/Caches/quotapace"
  agy_json > "$FAKE_HOME/Library/Caches/quotapace/antigravity.json"
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
expect_not_contains "Antigravity"

begin "heavy usage escalates to burning fast"
make_gh_ok 10 100
run_plugin
expect_contains "● Burning fast — may run out before reset"
expect_contains "90% used"
# Off-pace states must surface in the menu bar itself via the alert color.
expect_contains "90% | size=12.5 color="

begin "happy path writes the offline cache"
make_gh_ok
run_plugin
if [[ -s "$FAKE_HOME/Library/Caches/quotapace/quota.json" ]]; then
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
expect_contains "No AI quota sources detected"
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
expect_contains "No AI quota sources detected"

begin "missing jq names the fix"
GH_STUB=""
run_plugin QUOTAPACE_JQ=
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

# ---------------------------------------------------------------------------

echo
echo "passed ${PASS}, failed ${FAIL}"
[[ $FAIL -eq 0 ]]
