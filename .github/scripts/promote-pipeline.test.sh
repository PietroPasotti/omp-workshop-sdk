#!/usr/bin/env bash
# promote-pipeline.test.sh — test harness for promote-pipeline.sh
#
# Scenarios:
#   1. channel-revs: direct parser tests (token traps, multi-channel cells,
#      decoys, empty input)
#   2. empty store: all snapshot outputs empty; promote issues zero release calls
#   3. partial belt: edge + beta populated; beta->candidate and edge->beta only
#   4. full belt: two bases, token traps, multi-channel cell; exact release set;
#      no spurious calls from decoys 115/edge and 5/edge
#
# Run: bash .github/scripts/promote-pipeline.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE="$SCRIPT_DIR/promote-pipeline.sh"

PASS=0
FAIL=0

pass()  { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail()  { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n    expected: %s\n    actual:   %s\n' "$1" "$2" "$3"; }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then pass "$label"; else fail "$label" "$expected" "$actual"; fi
}

assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if printf '%s\n' "$haystack" | grep -qF "$needle"; then
        pass "$label"
    else
        fail "$label" "contains: $needle" "$haystack"
    fi
}

assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    if ! printf '%s\n' "$haystack" | grep -qF "$needle"; then
        pass "$label"
    else
        fail "$label" "NOT contains: $needle" "$haystack"
    fi
}

# ---------------------------------------------------------------------------
# Temp directory + mock sdkcraft
# ---------------------------------------------------------------------------
WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

MOCK_SDKCRAFT="$WORKDIR/sdkcraft"
cat > "$MOCK_SDKCRAFT" << 'MOCK_EOF'
#!/usr/bin/env bash
case "$1" in
    revisions)
        if [[ -f "${MOCK_REVISIONS_FILE:-}" ]]; then
            cat "$MOCK_REVISIONS_FILE"
        fi
        ;;
    release)
        printf 'release %s %s %s\n' "$2" "$3" "$4" >> "${MOCK_CALLS_FILE:?MOCK_CALLS_FILE not set}"
        ;;
    *)
        printf 'mock: unknown command: %s\n' "$*" >&2
        exit 1
        ;;
esac
MOCK_EOF
chmod +x "$MOCK_SDKCRAFT"

export SDKCRAFT="$MOCK_SDKCRAFT"
export MOCK_REVISIONS_FILE=""
export MOCK_CALLS_FILE="$WORKDIR/calls.txt"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# run_snapshot NAME TRACK [REVISIONS_FILE]
# Writes GITHUB_OUTPUT to a temp file and prints its contents.
run_snapshot() {
    local name="$1" track="$2" revisions_file="${3:-}"
    export MOCK_REVISIONS_FILE="$revisions_file"
    export GITHUB_OUTPUT="$WORKDIR/gho.txt"
    : > "$WORKDIR/gho.txt"
    bash "$PIPELINE" snapshot "$name" "$track"
    cat "$WORKDIR/gho.txt"
}

# get_output_val KEY OUTPUT_CONTENT
get_output_val() {
    local key="$1" content="$2"
    printf '%s\n' "$content" | grep "^${key}=" | sed "s/^${key}=//"
}

# run_promote NAME TRACK EDGE BETA CANDIDATE
# Returns recorded release calls (one per line).
run_promote() {
    local name="$1" track="$2" edge="$3" beta="$4" candidate="$5"
    : > "$WORKDIR/calls.txt"
    bash "$PIPELINE" promote "$name" "$track" "$edge" "$beta" "$candidate"
    cat "$WORKDIR/calls.txt"
}

count_lines() {
    printf '%s\n' "$1" | awk 'NF>0{c++} END{print c+0}'
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------
PARTIAL_FIXTURE="$WORKDIR/partial.txt"
cat > "$PARTIAL_FIXTURE" << 'EOF'
CHANNEL   REVISION  ARCHITECTURE       UPLOADED
15/edge   8         ubuntu@22.04:amd64 2026-06-01T10:00:00Z
15/edge   7         ubuntu@24.04:amd64 2026-06-01T10:00:00Z
15/beta   6         ubuntu@22.04:amd64 2026-05-28T10:00:00Z
15/beta   5         ubuntu@24.04:amd64 2026-05-28T10:00:00Z
EOF

FULL_FIXTURE="$WORKDIR/full.txt"
cat > "$FULL_FIXTURE" << 'EOF'
CHANNEL                    REVISION  ARCHITECTURE       UPLOADED
15/edge                    8         ubuntu@22.04:amd64 2026-06-01T10:00:00Z
15/edge                    7         ubuntu@24.04:amd64 2026-06-01T10:00:00Z
15/beta                    6         ubuntu@22.04:amd64 2026-05-28T10:00:00Z
15/beta                    5         ubuntu@24.04:amd64 2026-05-28T10:00:00Z
15/candidate,15/stable     4         ubuntu@22.04:amd64 2026-05-21T10:00:00Z
15/candidate,15/stable     3         ubuntu@24.04:amd64 2026-05-21T10:00:00Z
115/edge                   20        ubuntu@22.04:amd64 2026-06-01T09:00:00Z
5/edge                     1         ubuntu@22.04:amd64 2026-05-01T10:00:00Z
EOF

# ---------------------------------------------------------------------------
# Scenario A: channel-revs — direct parser
# ---------------------------------------------------------------------------
printf '\n=== channel-revs: direct parser ===\n'

TABLE=$(cat "$FULL_FIXTURE")

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "15/edge"      | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "15/edge → revs 8 7"                     "8 7" "$result"

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "15/beta"      | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "15/beta → revs 6 5"                     "6 5" "$result"

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "15/candidate" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "15/candidate → revs 4 3 (multi-cell)"   "4 3" "$result"

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "15/stable"    | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "15/stable → revs 4 3 (multi-cell)"      "4 3" "$result"

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "115/edge"     | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "decoy 115/edge → own rev 20 only"        "20"  "$result"

result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "5/edge"       | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_eq "decoy 5/edge → own rev 1 only"           "1"   "$result"

# 115/edge and 5/edge must not bleed into 15/edge results
result=$(printf '%s\n' "$TABLE" | bash "$PIPELINE" channel-revs "15/edge"      | tr '\n' ' ' | sed 's/[[:space:]]*$//')
assert_not_contains "115/edge decoy (rev 20) absent from 15/edge"  "20" "$result"
assert_not_contains "5/edge decoy (rev 1) absent from 15/edge"     "1"  "$result"

# Empty input
result=$(printf '\n' | bash "$PIPELINE" channel-revs "15/edge")
assert_eq "empty input → empty output"              ""    "$result"

# ---------------------------------------------------------------------------
# Scenario B: empty store
# ---------------------------------------------------------------------------
printf '\n=== snapshot: empty store ===\n'
output=$(run_snapshot "omp" "15" "")
assert_eq "empty: edge empty"       "" "$(get_output_val edge      "$output")"
assert_eq "empty: beta empty"       "" "$(get_output_val beta      "$output")"
assert_eq "empty: candidate empty"  "" "$(get_output_val candidate "$output")"

printf '\n=== promote: empty store → zero release calls ===\n'
calls=$(run_promote "omp" "15" "" "" "")
assert_eq "empty: zero release calls" "" "$calls"

# ---------------------------------------------------------------------------
# Scenario C: partial belt (edge + beta only)
# ---------------------------------------------------------------------------
printf '\n=== snapshot: partial belt ===\n'
output=$(run_snapshot "omp" "15" "$PARTIAL_FIXTURE")
assert_eq "partial: edge"      "8 7" "$(get_output_val edge      "$output")"
assert_eq "partial: beta"      "6 5" "$(get_output_val beta      "$output")"
assert_eq "partial: candidate" ""    "$(get_output_val candidate "$output")"

printf '\n=== promote: partial belt ===\n'
calls=$(run_promote "omp" "15" "8 7" "6 5" "")
assert_contains     "partial: beta 6 → 15/candidate"  "release omp 6 15/candidate" "$calls"
assert_contains     "partial: beta 5 → 15/candidate"  "release omp 5 15/candidate" "$calls"
assert_contains     "partial: edge 8 → 15/beta"       "release omp 8 15/beta"      "$calls"
assert_contains     "partial: edge 7 → 15/beta"       "release omp 7 15/beta"      "$calls"
assert_not_contains "partial: no stable promotion"     "stable"                     "$calls"
assert_eq           "partial: exactly 4 release calls" "4" "$(count_lines "$calls")"

# ---------------------------------------------------------------------------
# Scenario D: full belt, two bases, token traps
# ---------------------------------------------------------------------------
printf '\n=== snapshot: full belt ===\n'
output=$(run_snapshot "omp" "15" "$FULL_FIXTURE")
assert_eq "full: edge"      "8 7" "$(get_output_val edge      "$output")"
assert_eq "full: beta"      "6 5" "$(get_output_val beta      "$output")"
assert_eq "full: candidate" "4 3" "$(get_output_val candidate "$output")"

printf '\n=== promote: full belt — exact release set ===\n'
calls=$(run_promote "omp" "15" "8 7" "6 5" "4 3")

assert_contains "full: cand 4 → 15/stable,latest/stable" "release omp 4 15/stable,latest/stable" "$calls"
assert_contains "full: cand 3 → 15/stable,latest/stable" "release omp 3 15/stable,latest/stable" "$calls"
assert_contains "full: beta 6 → 15/candidate"             "release omp 6 15/candidate"             "$calls"
assert_contains "full: beta 5 → 15/candidate"             "release omp 5 15/candidate"             "$calls"
assert_contains "full: edge 8 → 15/beta"                  "release omp 8 15/beta"                  "$calls"
assert_contains "full: edge 7 → 15/beta"                  "release omp 7 15/beta"                  "$calls"

# No spurious calls: decoy revs 20 and 1 must not appear
assert_not_contains "full: decoy rev 20 not released" " 20 " "$calls"
assert_not_contains "full: decoy rev 1 not released"  " 1 "  "$calls"

assert_eq "full: exactly 6 release calls" "6" "$(count_lines "$calls")"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
