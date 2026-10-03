#!/usr/bin/env bash
# The failure-evidence helper of tests/ui-menus.sh never changes a verdict: under set -eu it returns 0 whatever fails.
set -u
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/tools/flea-sandbox-guard"

fail() {
    printf 'FAIL menus-evidence: %s\n' "$*" >&2
    exit 1
}

# Sample input, the first extracted line: 'menus_evidence() {'
helper=$(sed -n '/^menus_evidence() {/,/^}/p' "$repo/tests/ui-menus.sh")
[[ -n "$helper" ]] || fail "could not extract menus_evidence from tests/ui-menus.sh"

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-menus-evidence-XXXXXXXX") || fail "mktemp under $SANDBOX_ROOT failed"
: > "$test_root/$SANDBOX_MARKER" || fail "could not mark $test_root"
cleanup() { sandbox_remove "$test_root" 2>/dev/null || true; }
trap cleanup EXIT

# One case: the helper under errexit with every driver stubbed; shot is the omarchy-drive stub's body.
run_case() {
    local label="$1" evidence="$2" shot="$3" status
    case_output=$(
        set -eu
        ipc() { return 1; }
        hyprctl() { return 1; }
        omarchy-drive() { eval "$shot"; }
        evidence_dir="$evidence"
        eval "$helper"
        menus_evidence
        printf 'REACHED\n'
    ) 2>&1
    status=$?
    [[ "$status" -eq 0 ]] || fail "$label: the helper ended the run with status $status: $case_output"
    [[ "$case_output" == *REACHED* ]] || fail "$label: the run did not continue past the helper: $case_output"
}

run_case "failed capture" "$test_root/evidence" "return 1"
failed_shot=$case_output
grep -qx 'MENUS_EVIDENCE shot=failed' <<< "$failed_shot" || fail "a failed capture did not print its shot=failed line: $failed_shot"

: > "$test_root/blocker"
run_case "unwritable evidence dir" "$test_root/blocker/evidence" "return 0"
blocked=$case_output
grep -qx 'MENUS_EVIDENCE shot=failed' <<< "$blocked" || fail "an unwritable evidence dir did not print shot=failed: $blocked"

run_case "good capture" "$test_root/evidence" "return 0"
taken=$case_output
grep -q "^MENUS_EVIDENCE shot=$test_root/evidence/menus-failure-" <<< "$taken" || fail "a good capture did not name its png: $taken"
if grep -qx 'MENUS_EVIDENCE shot=failed' <<< "$taken"; then fail "a good capture said it failed: $taken"; fi
printf 'ok   menus_evidence returns 0 and says what happened under set -eu\n'
