#!/usr/bin/env bash
# Dry proof that colwatch_wait trusts a read only when the ipc call succeeded and the column is drawn.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
box=$(mktemp -d) || exit 1
: > "$box/.flea-test-sandbox"
# Removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    case $box in
        /?*) [ -f "$box/.flea-test-sandbox" ] && rm -rf -- "$box" ;;
    esac
}
trap cleanup EXIT
checks=0
bad=0
say() { local s=$*; printf '%s\n' "${s//FAIL/failed}"; }
# One dry call of the real colwatch_wait with a stubbed ipc; the stub body decides what the window answers.
# Sample input: dry 'printf seed.txt' create child has new.txt, answers "rc|output".
dry() {
    local stub="$1" out rc
    shift
    out=$(
        fail() { printf 'stub-fail: %s\n' "$*"; exit 7; }
        settle() { :; }
        eval "ipc() { $stub; }"
        colwatch_budget_s=${dry_budget:-0}
        # shellcheck source=tests/ui-colwatch.sh
        . "$repo/tests/ui-colwatch.sh"
        colwatch_poll_s=0.01
        colwatch_wait "$@"
    )
    rc=$?
    printf '%s|%s' "$rc" "$out"
}
# expect NAME WANT STUB STEP SLOT VERDICT NAME: WANT is pass (rc 0) or stale (rc 7).
expect() {
    local label="$1" want="$2" stub="$3" got rc
    shift 3
    got=$(dry "$stub" "$@")
    rc=${got%%|*}
    checks=$((checks + 1))
    if { [ "$want" = pass ] && [ "$rc" = 0 ]; } || { [ "$want" = stale ] && [ "$rc" = 7 ]; }; then
        say "ok   $label"
    else
        bad=$((bad + 1))
        say "BAD  $label: wanted $want, rc=$rc ${got#*|}"
    fi
}
expect "a failed ipc read never passes a gone step" stale 'return 1' s child gone new.txt
expect "an empty read from an undrawn column never passes a gone step" stale 'printf ""' s child gone new.txt
expect "a read without the column's anchor row never passes a gone step" stale 'printf "other.txt"' s child gone new.txt
expect "a drawn column still holding the name fails its gone step" stale 'printf "seed.txt|new.txt"' s child gone new.txt
expect "a drawn column without the name passes its gone step" pass 'printf "seed.txt"' s child gone new.txt
expect "the parent column is drawn by its own anchor row" pass 'printf "beside.txt|made.txt"' s parent gone new.txt
expect "a failed ipc read never passes a has step" stale 'return 1' s child has new.txt
expect "a drawn column with the name passes its has step" pass 'printf "seed.txt|new.txt"' s child has new.txt
# A read that fails twice and then answers: the failures keep polling and the later answer decides; the budget only bounds a wait that cannot end.
dry_budget=5
expect "failed reads keep polling until a real one answers" pass 'n=$(cat "$box/n" 2>/dev/null || echo 0); printf "%s" $((n + 1)) > "$box/n"; [ "$n" -ge 2 ] || return 1; printf "seed.txt"' s child gone new.txt
dry_budget=0
got=$(dry 'echo boom >&2; return 3' s child gone new.txt)
checks=$((checks + 1))
if [[ "$got" == *"exited 3"* ]]; then say "ok   the deadline failure names the last ipc error"; else bad=$((bad + 1)); say "BAD  the deadline failure does not name the ipc error: $got"; fi
if [ "$bad" -eq 0 ]; then printf 'colwatch-gate: %d checks, every verdict held\n' "$checks"; else printf 'colwatch-gate: FAIL %d of %d checks\n' "$bad" "$checks"; exit 1; fi
