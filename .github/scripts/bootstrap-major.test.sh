#!/usr/bin/env bash
# bootstrap-major.test.sh — static regression checks for bootstrap-major.yml
#
# Offline: reads the workflow file only. Never calls gh, sdkcraft, the
# network, or GitHub credentials, and never mutates tracked files.
#
# Invariants:
#   1. checkout uses ADMIN_TOKEN
#   2. side-effect step uses GH_TOKEN = ADMIN_TOKEN
#   3. preflight rejects empty GH_TOKEN and github-actions[bot], and runs
#      before any side effect
#   4. new-PR and already-open-PR paths exit before the default-branch PATCH
#   5. a remote VERSION check for ^${NEW_MAJOR}\. precedes the PATCH
#   6. the only default-branch mutation is the guarded PATCH
#
# Run: bash .github/scripts/bootstrap-major.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="$SCRIPT_DIR/../workflows/bootstrap-major.yml"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n    %s\n' "$1" "$2"; }

check() { # check NAME CONDITION_EXIT_CODE DETAIL
    if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1" "$3"; fi
}

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-major-test.XXXXXX")
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

[[ -f "$WORKFLOW" ]] || { echo "missing $WORKFLOW" >&2; exit 2; }

# Strip comment-only lines so assertions target executable/config content.
CODE="$WORKDIR/code.yml"
grep -vE '^[[:space:]]*#' "$WORKFLOW" > "$CODE"

# line_of PATTERN [N] — Nth (default first) line number in $CODE matching fixed string
line_of() {
    grep -nF -- "$1" "$CODE" | sed -n "${2:-1}p" | cut -d: -f1
}

printf '\n=== authentication ===\n'

rc=0; grep -qE '^[[:space:]]+token: \$\{\{ secrets\.ADMIN_TOKEN \}\}' "$CODE" || rc=$?
check "checkout uses token: secrets.ADMIN_TOKEN" "$rc" "no checkout token line"

# Bootstrap step section: from its name line to EOF.
STEP_START=$(grep -n 'name: Bootstrap track/' "$CODE" | head -1 | cut -d: -f1 || true)
if [[ -z "$STEP_START" ]]; then
    fail "bootstrap step present" "step 'Bootstrap track/...' not found"
    printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
STEP="$WORKDIR/step.yml"
tail -n +"$STEP_START" "$CODE" > "$STEP"

rc=0; grep -qE '^[[:space:]]+GH_TOKEN: \$\{\{ secrets\.ADMIN_TOKEN \}\}' "$STEP" || rc=$?
check "side-effect step has GH_TOKEN: secrets.ADMIN_TOKEN" "$rc" "GH_TOKEN env missing in bootstrap step"

rc=0; grep -qE '\[ -z "\$\{GH_TOKEN:-\}" \]' "$STEP" || rc=$?
check "preflight rejects empty GH_TOKEN" "$rc" "no empty-GH_TOKEN check"

rc=0; grep -qF '"github-actions[bot]" ]' "$STEP" || rc=$?
check "preflight rejects github-actions[bot] actor" "$rc" "no bot-actor rejection"

rc=0; grep -qF "gh api user --jq '.login'" "$STEP" || rc=$?
check "preflight resolves token identity via gh api user" "$rc" "no identity lookup"

# Preflight must precede every side effect.
PRE=$(grep -nF "gh api user --jq" "$STEP" | head -1 | cut -d: -f1 || true)
first_side=0
for pat in 'git config' 'git/refs' 'git push' 'gh pr create' 'gh pr merge' 'create-track' 'default_branch='; do
    n=$(grep -nF -- "$pat" "$STEP" | head -1 | cut -d: -f1 || true)
    if [[ -n "$n" && ( "$first_side" -eq 0 || "$n" -lt "$first_side" ) ]]; then first_side=$n; fi
done
rc=1
if [[ -n "$PRE" && "$first_side" -gt 0 && "$PRE" -lt "$first_side" ]]; then rc=0; fi
check "identity preflight precedes all side effects" "$rc" "preflight line=${PRE:-none}, first side effect line=$first_side"

printf '\n=== default-branch gating ===\n'

PATCH_COUNT=$(grep -cF 'default_branch=' "$STEP" || true)
check "exactly one default_branch mutation" "$([[ "$PATCH_COUNT" -eq 1 ]] && echo 0 || echo 1)" "found $PATCH_COUNT"

# The call spans a line continuation: `gh api "repos/..." \` then `-X PATCH ...`.
rc=1
if [[ -n "$(grep -nF -B1 -- '-X PATCH -f "default_branch=track/${NEW_MAJOR}"' "$STEP" | grep -F 'gh api "repos/${GITHUB_REPOSITORY}" \')" ]]; then rc=0; fi
check "default branch mutation is gh api -X PATCH default_branch=track/\${NEW_MAJOR}" "$rc" "PATCH form changed"

PATCH_LN=$(grep -nF 'default_branch=' "$STEP" | head -1 | cut -d: -f1 || true)

# Both pending paths must `exit 0` before the PATCH.
OPEN_LN=$(grep -nF 'elif [ -n "$OPEN_PR" ]' "$STEP" | head -1 | cut -d: -f1 || true)
rc=1
if [[ -n "$OPEN_LN" && -n "$PATCH_LN" ]]; then
    nxt=$(sed -n "$((OPEN_LN + 1)),$((OPEN_LN + 3))p" "$STEP")
    if printf '%s\n' "$nxt" | grep -qE '^[[:space:]]+exit 0$'; then rc=0; fi
fi
check "already-open setup PR path exits before default-branch PATCH" "$rc" "no 'exit 0' directly after OPEN_PR branch"

MERGE_LN=$(grep -nF 'gh pr merge --auto --merge --delete-branch' "$STEP" | head -1 | cut -d: -f1 || true)
rc=1
if [[ -n "$MERGE_LN" && -n "$PATCH_LN" ]]; then
    nxt=$(sed -n "$((MERGE_LN + 1)),$((MERGE_LN + 3))p" "$STEP")
    if printf '%s\n' "$nxt" | grep -qE '^[[:space:]]+exit 0$'; then rc=0; fi
fi
check "newly-created setup PR path exits before default-branch PATCH" "$rc" "no 'exit 0' after auto-merge enable"

# Gate: VERSION re-read + ^${NEW_MAJOR}\. match + error, all before PATCH.
GATE_ERR=$(grep -nF 'setup is not merged; refusing to change the default branch' "$STEP" | head -1 | cut -d: -f1 || true)
rc=1
if [[ -n "$GATE_ERR" && -n "$PATCH_LN" && "$GATE_ERR" -lt "$PATCH_LN" ]]; then rc=0; fi
check "unmerged-setup error precedes default-branch PATCH" "$rc" "gate error line=${GATE_ERR:-none}, PATCH line=${PATCH_LN:-none}"

GATE_CHECK=$(grep -nE '! printf .%s. "\$REMOTE_VERSION" \| grep -q "\^\$\{NEW_MAJOR\}\\\.' "$STEP" | head -1 | cut -d: -f1 || true)
rc=1
if [[ -n "$GATE_CHECK" && -n "$PATCH_LN" && "$GATE_CHECK" -lt "$PATCH_LN" ]]; then rc=0; fi
check "remote VERSION ^\${NEW_MAJOR}\\. check precedes default-branch PATCH" "$rc" "gate check line=${GATE_CHECK:-none}"

# The gate must refresh the remote ref before reading VERSION.
FETCH_LNS=$(grep -nF 'refs/heads/track/${NEW_MAJOR}:refs/remotes/origin/track/${NEW_MAJOR}' "$STEP" | cut -d: -f1 || true)
last_fetch=$(printf '%s\n' "$FETCH_LNS" | tail -1)
rc=1
if [[ -n "$last_fetch" && -n "$GATE_CHECK" && "$last_fetch" -lt "$GATE_CHECK" && "$last_fetch" -gt "${MERGE_LN:-0}" ]]; then rc=0; fi
check "gate re-fetches track/N after setup decision, before VERSION check" "$rc" "last fetch line=${last_fetch:-none}"

printf '\n=== no fallback / no bypass ===\n'

rc=0; grep -qE 'GH_TOKEN:.*GITHUB_TOKEN' "$STEP" && rc=1
check "bootstrap step never falls back to GITHUB_TOKEN" "$rc" "GITHUB_TOKEN referenced in side-effect step"

rc=0; grep -qE 'gh pr merge .*--admin' "$STEP" && rc=1
check "setup PR is never merged with --admin" "$rc" "--admin bypass present"

rc=0; grep -qE 'gh workflow run' "$CODE" && rc=1
check "no manual upload dispatch (push-triggered upload only)" "$rc" "gh workflow run present"

printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
