#!/usr/bin/env bash
# Display-free proof that every Permissions Apply wait polls to a deadline and the in-flight pause always resumes its backend.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
. "$repo/tests/ui-captures.sh"
. "$repo/tools/flea-sandbox-guard"
sandbox_root_ok
scratch=$(mktemp -d "$SANDBOX_ROOT/flea-capperm.XXXXXX") || exit 1
: > "$scratch/$SANDBOX_MARKER"
trap 'sandbox_remove "$scratch"' EXIT

checks=0
failed=0
apply_all="Permissions changed for 0 of 2, and 2 items keep their modes because a special bit is set: special.txt, x-special.txt."
foreign="y-foreign.txt keeps its mode because you do not own it."
applied="Permissions changed for 1 of 2, and special.txt keeps its mode because its setuid bit is set."
note="2 items keep their modes because a special bit is set: special.txt, x-special.txt."

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
# The harness's own pieces, each one a stub: this suite drives the helpers' logic and no display.
sandbox_scratch() { mkdir -p -- "$1"; }
click_row() { :; }
settle() { :; }
shot() { :; }
kill_flea() { printf 'kill\n' >> "$log"; }
backend_pids() { printf '4242\n'; }
convert_pause_backend() { printf 'pause %s\n' "$1" >> "$log"; }
permissions_resume_stopped() { [[ -z "$1" ]] || { printf 'resume %s\n' "$1" >> "$log"; printf '1\n' > "$sdir/resumed"; }; }
cap_permissions_focus() { :; }
# A sleep advances the shell's own clock, so a wait's deadline passes without a wall-clock second.
sleep() { SECONDS=$((SECONDS + 1)); }
# Each Return is one Apply and each open one card, which is what picks the state the reader answers.
key() { [[ "$1 $2" == "-k Return" ]] && bump returns; return 0; }
cap_permissions_open() { bump opens; }
bump() { printf '%s\n' "$(( $(cat "$sdir/$1") + 1 ))" > "$sdir/$1"; }
# A reply the card gives at its first read and then stops giving: the pre-state the old one-shot asserts read.
first_read() {
    local reads
    reads=$(cat "$sdir/reads")
    printf '%s\n' "$((reads + 1))" > "$sdir/reads"
    (( reads == 0 ))
}
closed_state='{"opened":false,"busy":false,"displayedError":"","controls":[]}'
flight_state='{"opened":true,"busy":true,"displayedError":"","controls":[{"name":"Cancel","enabled":false},{"name":"Close","enabled":false}]}'
idle_state='{"opened":true,"busy":false,"displayedError":"","controls":[{"name":"Cancel","enabled":true},{"name":"Close","enabled":true}]}'
ipc() {
    local returns opens resumed
    returns=$(cat "$sdir/returns")
    opens=$(cat "$sdir/opens")
    resumed=$(cat "$sdir/resumed")
    case "$1/$mode" in
        statusPrimary/skips|statusPrimary/stuck) (( returns == 1 )) && printf '%s\n' "$applied" || printf 'Permissions changed for 1 of 2, and %s\n' "$foreign" ;;
        permissionsState/skips|permissionsState/stuck)
            if (( returns == 1 && opens == 1 )); then printf '%s\n' "$closed_state"
            elif (( returns == 1 )); then printf '{"opened":true,"busy":false,"displayedError":"%s"}\n' "$note"
            elif (( returns == 2 && opens == 2 )); then
                if [[ "$mode" == stuck ]] || first_read; then printf '%s\n' "$idle_state"; else printf '{"opened":true,"busy":false,"displayedError":"%s"}\n' "$apply_all"; fi
            elif (( returns == 2 )); then printf '{"opened":true,"busy":false,"displayedError":"%s"}\n' "$foreign"
            else printf '%s\n' "$closed_state"; fi ;;
        permissionsState/flight|permissionsState/flightnow|permissionsState/never)
            if (( resumed == 1 )); then printf '%s\n' "$closed_state"
            elif [[ "$mode" == never || returns == 0 ]]; then printf '%s\n' "$idle_state"
            elif [[ "$mode" == flight ]] && first_read; then printf '%s\n' "$idle_state"
            else printf '%s\n' "$flight_state"; fi ;;
        *) return 2 ;;
    esac
}

# run NAME MODE FUNCTION: one helper in a fresh subshell and state dir; sets rc and log.
run() {
    name="$1"; mode="$2"
    sdir="$scratch/$name"
    log="$sdir/log"
    mkdir -p -- "$sdir"
    printf '0\n' > "$sdir/returns"; printf '0\n' > "$sdir/opens"; printf '0\n' > "$sdir/reads"; printf '0\n' > "$sdir/resumed"; : > "$log"
    (
        fixture_root="$sdir"
        unset SECONDS
        SECONDS=0
        # As tests/ui.sh runs a case: the parent's cleanup is cleared first.
        trap - EXIT
        "$3"
    ) > "$sdir/out" 2>&1
    rc=$?
}
expect() {
    checks=$((checks + 1))
    if [[ "$2" == "$3" ]]; then printf 'ok %s\n' "$1"; else printf 'FAIL %s: got [%s], want [%s]\n' "$1" "$2" "$3"; failed=$((failed + 1)); fi
}

run flight-settles flight cap_permissions_inflight
expect "inflight waits for the busy state, then resumes" "$rc $(tr '\n' ' ' < "$log")" "0 pause 4242 resume 4242 "
run flight-now flightnow cap_permissions_inflight
expect "inflight passes when the state is already there" "$rc" "0"
run flight-fail never cap_permissions_inflight
expect "inflight on a failed wait still resumes the backend and kills the window" "$rc $(tr '\n' ' ' < "$log")" "1 pause 4242 resume 4242 kill "
expect "an Apply wait that never settles ends at its own deadline" "$(grep -c 'Cancel and the close mark stay live while Apply is in flight, last state' "$sdir/out")" "1"
run skips-settle skips cap_permissions_skips
expect "skips wait for the all-skipped result the card settles on" "$rc $(grep -c . "$sdir/out")" "0 0"
run skips-stuck stuck cap_permissions_skips
expect "skips fail at a deadline, naming the card's last state" "$rc $(grep -c 'does not leave the card with .*last state' "$sdir/out")" "1 1"

printf 'ui-captures-permissions: %s checks, %s failed\n' "$checks" "$failed"
(( failed == 0 ))
