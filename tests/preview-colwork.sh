#!/bin/bash
# Counts per-move preview work and per-file opens after observed completions, including each frame decode target.
set -u
cd "$(dirname "$0")/.." || exit 1

for tool in qs magick ffmpeg inotifywait; do
    command -v "$tool" >/dev/null || { echo "preview-colwork.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-preview-colwork-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    wait 2>/dev/null
    # A failed run keeps its root, so every log path a FAIL line prints still points at a file.
    if [ "$result" -ne 0 ]; then
        printf 'preview-colwork: keeping %s\n' "$test_root"
        exit "$result"
    fi
    sandbox_remove "$test_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fx="$test_root/fx"
cache="$test_root/cache"
config_dir="$test_root/config"
runtime="$test_root/runtime"
log="$test_root/colwork.log"
swallowed_log="$test_root/swallowed.log"
watchlog="$test_root/watch.log"
opens="$test_root/opens.txt"
encoderlog="$test_root/encoder.log"
watch_deadline_s=15
watch_poll_s=0.02
qs_deadline_s=120
qs_self_stop_status=143
mkdir -p "$fx" "$cache" "$config_dir" "$test_root/home" "$runtime" "$test_root/tmp" || exit 1
chmod 700 "$runtime" || exit 1
ln -s "$PWD/tests/preview-colwork.qml" "$config_dir/shell.qml" || exit 1
ln -s "$PWD/ui" "$config_dir/flea" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$config_dir/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$config_dir/Ui" || exit 1

head -c 4000 src/json.rs > "$fx/00-start.txt" || exit 1
magick -size 2400x1600 plasma:fractal -seed 3 -quality 90 "$fx/10-photo.jpg" \
    || { echo "preview-colwork.sh: photo fixture generation failed"; exit 1; }
magick -size 3000x2000 plasma:fractal -seed 5 "$fx/20-large.png" \
    || { echo "preview-colwork.sh: png fixture generation failed"; exit 1; }
ffmpeg -y -nostdin -hide_banner -loglevel error -f lavfi -i testsrc=size=640x360:rate=30 -t 3 -pix_fmt yuv420p "$fx/30-clip.mp4" 2> "$encoderlog" \
    || ffmpeg -y -nostdin -hide_banner -loglevel error -f lavfi -i testsrc=size=640x360:rate=30 -t 3 -c:v mpeg4 "$fx/30-clip.mp4" 2>> "$encoderlog" \
    || { cat "$encoderlog" >&2; echo "preview-colwork.sh: clip fixture generation failed"; exit 1; }
[ -s "$fx/30-clip.mp4" ] || { cat "$encoderlog" >&2; echo "preview-colwork.sh: clip fixture is empty or missing"; exit 1; }
head -c 4000 src/main.rs > "$fx/40-notes.txt" || exit 1
magick \( -size 1700x2200 xc:white -fill black -draw 'rectangle 100,100 1599,400' \) \( -size 1700x2200 xc:gray80 \) "$fx/50-manual.pdf" \
    || { echo "preview-colwork.sh: pdf fixture generation failed"; exit 1; }
cp "$fx/10-photo.jpg" "$fx/60-photo.heic" || exit 1
cp src/json.rs "$fx/70-code.rs" || exit 1
magick "$fx/10-photo.jpg" -resize 512x "$cache/t1.png" || exit 1
magick "$fx/20-large.png" -resize 512x "$cache/t2.png" || exit 1
magick -size 640x360 plasma:fractal -seed 9 -resize 512x "$cache/t3.png" || exit 1
magick "$fx/50-manual.pdf[0]" -resize 512x "$cache/t5.png" 2>/dev/null || magick -size 396x512 xc:white "$cache/t5.png" || exit 1
magick "$fx/60-photo.heic" -resize 512x "$cache/t6.png" 2>/dev/null || cp "$cache/t1.png" "$cache/t6.png" || exit 1

inotifywait -m -e open -e create --format '%e|%f' "$fx" "$cache" > "$watchlog" 2>&1 &
watcher=$!

wait_watch() {
    timeout "$watch_deadline_s" bash -s -- "$1" "$watchlog" "$watch_poll_s" <<'WAIT_WATCH'
coproc events { exec tail -n +1 --sleep-interval="$3" -f "$2"; }
event_reader_pid=$events_PID
trap 'kill "$event_reader_pid" 2>/dev/null; wait "$event_reader_pid" 2>/dev/null' EXIT
# Sample input: CREATE|.mark-done
while IFS= read -r line <&"${events[0]}"; do
    [ "$line" = "$1" ] && exit 0
done
exit 1
WAIT_WATCH
}
wait_watch 'Watches established.' || { echo "COLWORK FAIL watcher readiness deadline (watch $watchlog)"; exit 1; }

run_harness() {
    local swallow="$1" output="$2"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root/tmp" \
        XDG_CONFIG_HOME="$test_root/home/.config" XDG_STATE_HOME="$test_root/home/.local/state" \
        XDG_CACHE_HOME="$test_root/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 \
        QT_FORCE_STDERR_LOGGING=1 \
        CW_DIR="$fx" CW_CACHE="$cache" CW_WATCHLOG="$watchlog" CW_SWALLOW_REPLY="$swallow" \
        timeout "$qs_deadline_s" qs -p "$config_dir" > "$output" 2>&1 )
}
run_harness 0 "$log"
status=$?
watch_done=0
wait_watch "CREATE|.mark-done" && watch_done=1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

checks=0
failed=0
say_pass() { printf 'COLWORK PASS %s\n' "$*"; checks=$((checks + 1)); }
say_fail() { printf 'COLWORK FAIL %s\n' "$*"; checks=$((checks + 1)); failed=$((failed + 1)); }

run_harness 1 "$swallowed_log"
swallowed_status=$?
if [ "$swallowed_status" -eq "$qs_self_stop_status" ] \
    && grep -aq 'COLWORK SWALLOWED meta token=' "$swallowed_log" \
    && grep -aq 'COLWORK STEP col1 meta=1 replies=0 ' "$swallowed_log" \
    && grep -aq 'COLWORK FAIL col1 replies got=0 want=1' "$swallowed_log" \
    && grep -aq 'COLWORK FAIL col1 deadline waiting for work got=false want=true' "$swallowed_log" \
    && grep -aq 'COLWORK QMLTALLY passed=' "$swallowed_log"; then
    say_pass "swallowed metadata reply leaves meta=1 replies=0 and fails col1 at its deadline"
else
    say_fail "swallowed metadata reply was not detected (qs exit $swallowed_status, log $swallowed_log)"
fi

[ "$watch_done" -eq 1 ] || say_fail "done marker deadline (watch $watchlog)"

if ! grep -aq 'COLWORK QMLTALLY' "$log"; then
    say_fail "the harness did not finish (qs exit $status, log $log)"
    grep -a 'COLWORK FAIL' "$log" | head -20
    printf 'COLWORK DONE checks=%s failed=%s\n' "$checks" "$failed"
    exit 1
fi
# The QML verdicts are the suite's own lines, re-emitted so one output holds every check.
while IFS= read -r line; do
    line=${line##*COLWORK }
    case "$line" in
        PASS*) say_pass "${line#PASS }" ;;
        FAIL*) say_fail "${line#FAIL }" ;;
        STEP*) printf 'COLWORK %s\n' "$line" ;;
    esac
done < <(grep -a 'COLWORK \(PASS\|FAIL\|STEP\)' "$log")
# The gate judges preview work; pre-existing offscreen platform warnings remain outside its scope.
declare -A phase_opens=()
phase=""
# Sample input: CREATE|.mark-leg, followed by OPEN|t1.png
while IFS='|' read -r event file; do
    case "$event|$file" in
        CREATE'|'.mark-*) phase=${file#.mark-}; continue ;;
    esac
    case "$event" in *OPEN*) ;; *) continue ;; esac
    [ -n "$phase" ] || continue
    case "$file" in .mark-*) continue ;; esac
    key="$phase|$file"
    phase_opens[$key]=$(( ${phase_opens[$key]:-0} + 1 ))
done < "$watchlog"
for key in "${!phase_opens[@]}"; do
    printf '%s %s\n' "$key" "${phase_opens[$key]}"
done | sort > "$opens"
want_opens() {
    local phase="$1" file="$2" want="$3" mode="${4:-exact}" got
    # Sample input: leg|t1.png 1
    got=$(awk -v k="$phase|$file" '$1 == k { print $2 }' "$opens")
    [ -z "$got" ] && got=0
    if [ "$got" -eq "$want" ] || { [ "$mode" = at-most ] && [ "$got" -ge 1 ] && [ "$got" -le "$want" ]; }; then
        say_pass "opens $phase $file count=$got"
    else
        say_fail "opens $phase $file opened $got time(s), want $mode $want (log $log watch $watchlog)"
    fi
}
want_phase_only() {
    local phase="$1" want="$2" got
    # Sample input: leg|t1.png 1
    got=$(grep -c -- "^$phase|" "$opens")
    if [ "$got" -eq "$want" ]; then
        say_pass "opens $phase no file besides the $want expected"
    else
        say_fail "opens $phase $got distinct file(s), want $want (watch $watchlog)"
    fi
}
phase_counter_cases() (
    opens="$test_root/phase-counter.txt"
    failed=0
    # Sample input: leg|t1.png 10, ql|10-photo.jpg 1 and qlf|20-large.png 1.
    printf '%s\n' 'leg|t1.png 10' 'leg|t2.png 1' 'legacy|t3.png 1' 'ql|10-photo.jpg 1' 'qlf|20-large.png 1' > "$opens"
    say_pass() { :; }
    say_fail() {
        printf 'phase counter: %s\n' "$*" >&2
        failed=$((failed + 1))
    }
    want_phase_only leg 2
    want_phase_only ql 1
    want_phase_only qlf 1
    want_phase_only missing 0
    [ "$failed" -eq 0 ]
)
if phase_counter_cases; then
    say_pass "phase counter handles exact prefixes and an absent phase"
else
    say_fail "phase counter miscounts prefixes or an absent phase"
fi
# Each departing file stays closed; cached frames and ordinary Quick Look sources open once.
want_opens leg 40-notes.txt 1
# PDF permits one document open plus one type sniff, including the column page reader.
want_opens leg 50-manual.pdf 2 at-most
want_opens leg 70-code.rs 1
want_opens leg t1.png 1
want_opens leg t2.png 1
want_opens leg 20-large.png 1
want_opens leg t3.png 1
want_opens leg t5.png 1
want_opens leg t6.png 1
want_phase_only leg 9
want_opens ql 00-start.txt 1
want_opens ql 10-photo.jpg 1
want_opens ql 20-large.png 1
want_opens ql 40-notes.txt 1
# PDF permits one document open plus one type sniff.
want_opens ql 50-manual.pdf 2 at-most
# The HEIC-named JPEG permits one type sniff plus one image decode open.
want_opens ql 60-photo.heic 2 at-most
want_opens ql 70-code.rs 1
want_phase_only ql 7
want_opens qlf 10-photo.jpg 1
want_opens qlf 20-large.png 1
want_phase_only qlf 2

# A bare FAIL line is what qs-suite.sh greps for; the DONE line below stays last.
[ "$failed" -eq 0 ] || printf 'FAIL preview-colwork: %s of %s check(s) failed (log %s watch %s)\n' "$failed" "$checks" "$log" "$watchlog"
printf 'COLWORK DONE checks=%s failed=%s\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
