#!/usr/bin/env bash
# promote-pipeline.sh — release-promotion conveyor helpers
#
# Subcommands:
#   snapshot    NAME TRACK    — capture pre-upload channel state → GITHUB_OUTPUT
#   promote     NAME TRACK EDGE BETA CANDIDATE — cascade revisions down the belt
#   channel-revs TARGET       — parse a `sdkcraft revisions` table on stdin (test hook)
#
# Environment:
#   SDKCRAFT   override the sdkcraft binary (test injection point; default: sdkcraft)
#   DRY_RUN    when set (non-empty), `_release` prints the would-be sdkcraft
#              release command and skips the store write (snapshot/parse are
#              read-only and unaffected)
#
# Revision order:
#   candidate -> TRACK/stable,latest/stable
#   beta      -> TRACK/candidate
#   edge      -> TRACK/beta
#
# EDGE / BETA / CANDIDATE are space-separated lists of revision numbers (one per
# base/arch).  An empty list is a no-op for that tier.

set -euo pipefail

SDKCRAFT=${SDKCRAFT:-sdkcraft}

# ---------------------------------------------------------------------------
# channel_revs TARGET
#   Read a `sdkcraft revisions` table on stdin.
#   Print the REVISION number of every row whose CHANNEL cell contains TARGET
#   as an exact comma-delimited token — avoids "15/edge" matching "115/edge".
#
#   Table format: CHANNEL  REVISION  ARCHITECTURE  UPLOADED
#   CHANNEL may be a comma-joined list (no spaces) when a revision is in
#   multiple channels.  Rows whose second field is not a plain integer are
#   ignored (header + any craft-cli status noise).
# ---------------------------------------------------------------------------
channel_revs() {
    local target="$1"
    awk -v target="$target" '
        $2 ~ /^[0-9]+$/ {
            n = split($1, ch, ",")
            for (i = 1; i <= n; i++) {
                if (ch[i] == target) {
                    print $2
                    break
                }
            }
        }
    '
}

# ---------------------------------------------------------------------------
# _revisions NAME
#   Run `sdkcraft revisions NAME`, retrying up to 3 times on transient failure.
#   On persistent failure: warn to stderr, print nothing, return 0
#   (first-ever release and outages no-op the belt instead of corrupting it).
# ---------------------------------------------------------------------------
_revisions() {
    local name="$1" attempt output
    for attempt in 1 2 3; do
        if output=$("$SDKCRAFT" revisions "$name" 2>/dev/null); then
            printf '%s' "$output"
            return 0
        fi
        [[ $attempt -lt 3 ]] && sleep $((attempt * 2))
    done
    echo "WARNING: 'sdkcraft revisions $name' failed after 3 attempts; treating belt as empty" >&2
    return 0
}

# ---------------------------------------------------------------------------
# _release NAME REVISION CHANNELS
#   Run `sdkcraft release`, retrying up to 3 times on failure.
#   When DRY_RUN is set, print the would-be command and skip the store write.
# ---------------------------------------------------------------------------
_release() {
    local name="$1" rev="$2" channels="$3" attempt
    if [[ -n "${DRY_RUN:-}" ]]; then
        echo "DRY-RUN: would run: $SDKCRAFT release $name $rev $channels"
        return 0
    fi
    for attempt in 1 2 3; do
        if "$SDKCRAFT" release "$name" "$rev" "$channels"; then
            return 0
        fi
        [[ $attempt -lt 3 ]] && sleep $((attempt * 2))
    done
    echo "ERROR: 'sdkcraft release $name $rev $channels' failed after 3 attempts" >&2
    return 1
}

# ---------------------------------------------------------------------------
# _emit KEY VALUE
#   Append KEY=VALUE to $GITHUB_OUTPUT when set; otherwise print to stdout.
# ---------------------------------------------------------------------------
_emit() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
    else
        printf '%s=%s\n' "$1" "$2"
    fi
}

# ---------------------------------------------------------------------------
# cmd_snapshot NAME TRACK
# ---------------------------------------------------------------------------
cmd_snapshot() {
    local name="$1" track="$2"
    local table edge beta candidate

    table=$(_revisions "$name")

    edge=$(      printf '%s\n' "$table" | channel_revs "${track}/edge"      | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    beta=$(       printf '%s\n' "$table" | channel_revs "${track}/beta"      | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    candidate=$(  printf '%s\n' "$table" | channel_revs "${track}/candidate" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    _emit edge      "$edge"
    _emit beta      "$beta"
    _emit candidate "$candidate"
}

# ---------------------------------------------------------------------------
# cmd_promote NAME TRACK EDGE BETA CANDIDATE
#   EDGE / BETA / CANDIDATE: space-separated revision number lists.
#   Unquoted expansion is intentional — word-splits the lists into loop args.
# ---------------------------------------------------------------------------
cmd_promote() {
    local name="$1" track="$2" edge="$3" beta="$4" candidate="$5"

    # candidate -> <N>/stable,latest/stable
    # shellcheck disable=SC2086
    for rev in $candidate; do
        _release "$name" "$rev" "${track}/stable,latest/stable"
    done

    # beta -> <N>/candidate
    # shellcheck disable=SC2086
    for rev in $beta; do
        _release "$name" "$rev" "${track}/candidate"
    done

    # edge -> <N>/beta
    # shellcheck disable=SC2086
    for rev in $edge; do
        _release "$name" "$rev" "${track}/beta"
    done
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
    snapshot)
        [[ $# -eq 3 ]] || { echo "Usage: $0 snapshot NAME TRACK" >&2; exit 1; }
        cmd_snapshot "$2" "$3"
        ;;
    promote)
        [[ $# -eq 6 ]] || { echo "Usage: $0 promote NAME TRACK EDGE BETA CANDIDATE" >&2; exit 1; }
        cmd_promote "$2" "$3" "$4" "$5" "$6"
        ;;
    channel-revs)
        [[ $# -eq 2 ]] || { echo "Usage: $0 channel-revs TARGET" >&2; exit 1; }
        channel_revs "$2"
        ;;
    *)
        echo "Usage: $0 {snapshot|promote|channel-revs} ..." >&2
        exit 1
        ;;
esac
