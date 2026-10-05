#!/usr/bin/env bash
# A qs log holding "Quickshell has crashed" fails its leg whatever qs exited with, and its crash reports outlive the run.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
MARKER=.flea-test-sandbox
box=$(mktemp -d) || exit 1
: > "$box/$MARKER"
# Removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    case $box in
        /?*) [ -f "$box/$MARKER" ] && rm -rf -- "$box" ;;
    esac
}
trap cleanup EXIT
checks=0
bad=0
# The verdict word is reworded in every line this suite prints, so only a real failure reads as one to flea-ci.
say() { local s=$*; printf '%s\n' "${s//FAIL/failed}"; }
check() {
    checks=$((checks + 1))
    if [ "$1" = ok ]; then say "ok   $2"; else bad=$((bad + 1)); say "BAD  $2"; fi
}

# The helper alone: the crash line with its colour codes, and a clean log.
. tests/qslog-gate.sh
# Direct calls below need the guard's own report function.
. tools/flea-sandbox-guard
printf '\033[31m ERROR\033[0m: Quickshell has crashed under pid 15810 (Coredumps will be available under that pid.)\n' > "$box/crashed.log"
printf 'QLFF DONE steps=14 failures=0\n' > "$box/clean.log"
line=$(qslog_crash "leg x" "$box/crashed.log"); rc=$?
[ "$rc" -eq 1 ] && [ "$line" = 'FAIL leg x:  ERROR: Quickshell has crashed under pid 15810 (Coredumps will be available under that pid.)' ] \
    && check ok "the crash line fails the leg and is printed without colour codes" || check bad "the crash line fails the leg and is printed without colour codes"
qslog_crash "leg x" "$box/clean.log" > /dev/null && check ok "a clean log passes" || check bad "a clean log passes"

# The whole suite against a stub qs that prints DONE once, then crashes, restarts and exits 0: the crash handler's rerun must not pass.
mkdir -p "$box/bin" "$box/fixtures" "$box/logs" || exit 1
cat > "$box/bin/qs" <<'STUB'
#!/bin/sh
mkdir -p "$XDG_CACHE_HOME/quickshell/crashes/stub1" && echo "backtrace stub" > "$XDG_CACHE_HOME/quickshell/crashes/stub1/log.txt"
echo "QLFF DONE steps=1 failures=0"
echo "ERROR: Quickshell has crashed under pid 1 (Coredumps will be available under that pid.)"
exit 0
STUB
chmod +x "$box/bin/qs"
out=$(env PATH="$box/bin:$PATH" FLEA_FIXTURE_ROOT="$box/fixtures" FLEA_CI_SUITE_LOGS="$box/logs" bash tests/quicklook-firstframe.sh 2>&1); rc=$?
[ "$rc" -ne 0 ] && grep -q 'FAIL quicklook-firstframe order: .*Quickshell has crashed under pid 1' <<< "$out" \
    && check ok "quicklook-firstframe fails a leg on the crash line though qs exited 0" || check bad "quicklook-firstframe fails a leg on the crash line though qs exited 0"
[ -f "$box/logs/quicklook-firstframe.sh-crashes/order_cache_quickshell_crashes_stub1/log.txt" ] \
    && check ok "the crash report is copied beside the leg log" || check bad "the crash report is copied beside the leg log"

# Any suite that removes its sandbox: a crash report left in it is a FAIL line and a copy, though the suite itself checked nothing.
cat > "$box/stub-suite.sh" <<'STUB'
#!/usr/bin/env bash
. "$1/tools/flea-sandbox-guard"
root="$FIXTURE_ROOT/stub-root"
sandbox_make "$root"
mkdir -p "$root/leg/cache/quickshell/crashes/t2cdhbfmt" && echo "backtrace stub" > "$root/leg/cache/quickshell/crashes/t2cdhbfmt/log.txt"
sandbox_remove "$root"
STUB
out=$(env FLEA_FIXTURE_ROOT="$box/fixtures" FLEA_CI_SUITE_LOGS="$box/logs" bash "$box/stub-suite.sh" "$PWD" 2>&1)
grep -q 'FAIL stub-suite.sh: Quickshell has crashed, report leg/cache/quickshell/crashes/t2cdhbfmt$' <<< "$out" \
    && check ok "a suite that only removes its sandbox still prints the crash as a FAIL line" || check bad "a suite that only removes its sandbox still prints the crash as a FAIL line"
[ -f "$box/logs/stub-suite.sh-crashes/leg_cache_quickshell_crashes_t2cdhbfmt/log.txt" ] \
    && check ok "and keeps the report" || check bad "and keeps the report"

# A missing log is a FAIL of its own, never a clean log.
qslog_crash "leg x" "$box/no-such.log" > "$box/missing.out" 2>&1
rc=$?
status=bad
if grep -q 'FAIL leg x: cannot read log' "$box/missing.out"; then
    if [ "$rc" -eq 1 ]; then
        status=ok
    fi
fi
check "$status" "a missing log is a FAIL with its own message"

# A path grep cannot read as a file is the same FAIL.
qslog_crash "leg x" "$box" > "$box/dir.out" 2>&1
rc=$?
status=bad
if grep -q 'FAIL leg x: cannot read log' "$box/dir.out"; then
    if [ "$rc" -eq 1 ]; then
        status=ok
    fi
fi
check "$status" "an unreadable log is a FAIL with its own message"

# A crash report the suite cannot copy still names its source and destination.
failroot="$box/failcopy/root"
mkdir -p "$failroot/leg/cache/quickshell/crashes/aaa"
echo "backtrace stub" > "$failroot/leg/cache/quickshell/crashes/aaa/log.txt"
: > "$box/logsfile"
out=$(FLEA_CI_SUITE_LOGS="$box/logsfile" sandbox_crash_report "$failroot" 2>&1)
status=bad
if grep -q 'FAIL .*cannot copy crash report .* to .*' <<< "$out"; then
    status=ok
fi
check "$status" "a failed copy is a FAIL naming source and destination"

# A second report for the same name gets the next free name: both kept, neither nested, nothing deleted.
nestroot="$box/nest/root"
mkdir -p "$nestroot/leg/cache/quickshell/crashes/aaa"
echo "first" > "$nestroot/leg/cache/quickshell/crashes/aaa/log.txt"
FLEA_CI_SUITE_LOGS="$box/nestlogs" sandbox_crash_report "$nestroot" > /dev/null 2>&1
echo "second" > "$nestroot/leg/cache/quickshell/crashes/aaa/log.txt"
FLEA_CI_SUITE_LOGS="$box/nestlogs" sandbox_crash_report "$nestroot" > /dev/null 2>&1
unset FLEA_CI_SUITE_LOGS
nestdest="$box/nestlogs/${0##*/}-crashes/leg_cache_quickshell_crashes_aaa"
status=bad
if [ "$(cat "$nestdest/log.txt")" = "first" ] && [ "$(cat "$nestdest.1/log.txt" 2>/dev/null)" = "second" ]; then
    if [ ! -e "$nestdest/aaa" ]; then
        status=ok
    fi
fi
check "$status" "a second report for the same name gets the next free name instead of nesting"

# A crash report older than this run is stale, never a FAIL for this run.
staleroot="$box/stale/root"
mkdir -p "$staleroot/leg/cache/quickshell/crashes/old1"
echo "backtrace stub" > "$staleroot/leg/cache/quickshell/crashes/old1/log.txt"
stale_date='2000-01-01 00:00:00'
touch -d "$stale_date" "$staleroot/leg/cache/quickshell/crashes/old1" "$staleroot/leg/cache/quickshell/crashes/old1/log.txt"
out=$(sandbox_crash_report "$staleroot" 2>&1)
status=bad
if grep -q 'stale crash report from an earlier run' <<< "$out"; then
    if ! grep -q 'FAIL' <<< "$out"; then
        status=ok
    fi
fi
check "$status" "a stale crash report is reported without FAIL"

printf 'qslog-crash: %s checks, %s bad\n' "$checks" "$bad"
[ "$bad" -eq 0 ]
