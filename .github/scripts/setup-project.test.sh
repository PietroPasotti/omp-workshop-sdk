#!/usr/bin/env bash
# Run: bash .github/scripts/setup-project.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../../hooks/setup-project"
WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1" >&2; }

for format in yml yaml json; do
    home="$WORKDIR/existing $format"
    config="$home/.omp/agent/models.$format"
    expected="$WORKDIR/expected.$format"
    mkdir -p "$home/.omp/agent"
    if [[ "$format" == json ]]; then
        printf '%s\n' '{"providers":{"custom":{"baseUrl":"https://example.invalid","apiKey":"user-token","api":"anthropic-messages"}}}' > "$config"
    else
        printf '%s\n' '# User configuration: preserve these bytes.' 'providers:' '  custom:' '    baseUrl: https://example.invalid' '    apiKey: user-token' '    api: anthropic-messages' > "$config"
    fi
    cp "$config" "$expected"

    HOME="$home" bash "$HOOK"
    if cmp -s "$expected" "$config"; then
        pass
    else
        fail "existing models.$format was changed"
    fi
    if [[ "$format" != yml ]]; then
        if [[ ! -e "$home/.omp/agent/models.yml" ]]; then
            pass
        else
            fail "models.yml was seeded and shadows existing models.$format"
        fi
    fi
done

home="$WORKDIR/fresh home"
HOME="$home" bash "$HOOK"
config="$home/.omp/agent/models.yml"
if [[ -f "$config" ]]; then
    pass
    contents=$(< "$config")
    if [[ "$contents" == *'baseUrl: http://localhost:4000'* ]]; then
        pass
    else
        fail 'fresh config is missing the gateway URL'
    fi
    if [[ "$contents" == *'apiKey: "!workshopctl get-secret omp.omp-gateway-token"'* ]]; then
        pass
    else
        fail 'fresh config is missing the workshopctl token command'
    fi
    cp "$config" "$WORKDIR/seeded.yml"
    HOME="$home" bash "$HOOK"
    if cmp -s "$WORKDIR/seeded.yml" "$config"; then
        pass
    else
        fail 'repeat setup changed the seeded config'
    fi
else
    fail 'fresh home did not receive models.yml'
fi

printf 'setup-project: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
