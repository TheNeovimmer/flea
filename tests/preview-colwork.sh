#!/bin/bash
# The column preview's per-move work as a count gate: one decode request per idle
# move at the target size, never the departing row's cache file again. Drives the
# real ColumnsArea, SelectionPreview, PreviewColumn, PreviewSwap and Preview over
# a stub pane and 8 real files, offscreen, and judges exact per-move counts plus
# per-file open counts. Counts only, never wall-clock time.
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
watchlog="$test_root/watch.log"
opens="$test_root/opens.txt"
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
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc=size=640x360:rate=30 -t 3 -pix_fmt yuv420p "$fx/30-clip.mp4" \
    || ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc=size=640x360:rate=30 -t 3 -c:v mpeg4 "$fx/30-clip.mp4" \
    || { echo "preview-colwork.sh: clip fixture generation failed"; exit 1; }
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

# Sample input, one inotifywait line per event: 'OPEN|t1.png' is one open of the
# new row's cache file, 'CREATE|.mark-ql' opens the next phase once this one closes.
inotifywait -m -e open -e create --format '%e|%f' "$fx" "$cache" > "$watchlog" 2>&1 &
watcher=$!

( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root/tmp" \
    XDG_CONFIG_HOME="$test_root/home/.config" XDG_STATE_HOME="$test_root/home/.local/state" \
    XDG_CACHE_HOME="$test_root/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 \
    QT_FORCE_STDERR_LOGGING=1 \
    CW_DIR="$fx" CW_CACHE="$cache" \
    timeout 120 qs -p "$config_dir" > "$log" 2>&1 )
status=$?
# The watch outlives qs by a breath so its last events flush before it is read.
sleep 1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

checks=0
failed=0
say_pass() { printf 'COLWORK PASS %s\n' "$*"; checks=$((checks + 1)); }
say_fail() { printf 'COLWORK FAIL %s\n' "$*"; checks=$((checks + 1)); failed=$((failed + 1)); }

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
    esac
done < <(grep -a 'COLWORK \(PASS\|FAIL\)' "$log")
# The counts above are the whole gate: a QML error loud enough to matter moves
# one of them, and the tree's own pre-existing offscreen warnings (FileDrag's
# Connections, the platform mask) are not this suite's subject to judge.

# Per-file opens per phase, from the .mark-* boundaries the harness touches.
awk -F'|' '
    $2 == ".mark-leg" { ph = "leg"; next }
    $2 == ".mark-ql" { ph = "ql"; next }
    $2 == ".mark-qlf" { ph = "qlf"; next }
    $2 == ".mark-done" { ph = "done"; next }
    $1 ~ /OPEN/ && ph != "" && $2 !~ /^\.mark/ { n[ph "|" $2]++ }
    END { for (k in n) print k " " n[k] }' "$watchlog" | sort > "$opens"
want_opens() {
    # Sample input: 'want_opens leg t1.png 1' passes only when the leg opened t1.png exactly once.
    local phase="$1" file="$2" want="$3" got
    got=$(awk -v k="$phase|$file" '$1 == k { print $2 }' "$opens")
    [ -z "$got" ] && got=0
    if [ "$got" -eq "$want" ]; then
        say_pass "opens $phase $file count=$got"
    else
        say_fail "opens $phase $file opened $got time(s), want $want (log $log watch $watchlog)"
    fi
}
want_phase_only() {
    # Sample input: 'want_phase_only leg 8' passes only when the leg opened exactly 8 distinct files.
    local phase="$1" want="$2" got
    got=$(awk -v p="$phase|" 'index($1, p) == 1 { c++ } END { print c + 0 }' "$opens")
    if [ "$got" -eq "$want" ]; then
        say_pass "opens $phase no file besides the $want expected"
    else
        say_fail "opens $phase $got distinct file(s), want $want (watch $watchlog)"
    fi
}
# The current tree's own per-file lines: each new row's cache file once per leg,
# no departing row's file opened again; Quick Look opens each source once (the
# manual twice, the heic-wrapped JPEG twice), the follow opens only the PNG.
want_opens leg 40-notes.txt 1
want_opens leg 50-manual.pdf 2
want_opens leg 70-code.rs 1
want_opens leg t1.png 1
want_opens leg t2.png 1
want_opens leg t3.png 1
want_opens leg t5.png 1
want_opens leg t6.png 1
want_phase_only leg 8
want_opens ql 00-start.txt 1
want_opens ql 10-photo.jpg 1
want_opens ql 20-large.png 1
want_opens ql 40-notes.txt 1
want_opens ql 50-manual.pdf 2
want_opens ql 60-photo.heic 2
want_opens ql 70-code.rs 1
want_phase_only ql 7
want_opens qlf 10-photo.jpg 1
want_opens qlf 20-large.png 1
want_phase_only qlf 2

# A bare FAIL line is what qs-suite.sh greps for; the DONE line below stays last.
[ "$failed" -eq 0 ] || printf 'FAIL preview-colwork: %s of %s check(s) failed (log %s watch %s)\n' "$failed" "$checks" "$log" "$watchlog"
printf 'COLWORK DONE checks=%s failed=%s\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
