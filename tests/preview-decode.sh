#!/bin/bash
# The Columns preview as v0.3.4 drew it (the cache file, the original only where none exists) and Quick Look's decode, offscreen; see AGENTS.md "File budget".
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick exiv2 inotifywait; do
    command -v "$tool" >/dev/null || { echo "preview-decode.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-preview-decode-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    wait 2>/dev/null
    # A failed run keeps its root, so every log path a FAIL line prints still points at a file.
    if [ "$result" -ne 0 ]; then
        printf 'preview-decode: keeping %s\n' "$test_root"
        exit "$result"
    fi
    sandbox_remove "$test_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

config_dir="$test_root/config"
photos="$test_root/photos"
runtime="$test_root/runtime"
log="$test_root/preview.log"
watchlog="$test_root/watch.log"
mkdir -p "$config_dir" "$photos" "$runtime" || exit 1
chmod 700 "$runtime" || exit 1
ln -s "$PWD/tests/preview-decode.qml" "$config_dir/shell.qml" || exit 1
ln -s /usr/share/omarchy/shell/Commons "$config_dir/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$config_dir/Ui" || exit 1

# Fifty sweep photos with a cache file each, the 6016x3900 PNG rest row and a text start row; only open events are counted, never pixels.
printf 'preview decode rest row, not an image\n' > "$photos/note.txt" \
    || { echo "preview-decode.sh: text fixture generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 3 "$photos/seed0.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 11 "$photos/seed1.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick "$photos/seed0.jpg" -resize 256x "$photos/thumb.png" \
    || { echo "preview-decode.sh: thumbnail generation failed"; exit 1; }
magick -size 6016x3900 xc:gray50 -fill black -draw 'rectangle 0,0 3007,3899' "$photos/big.png" \
    || { echo "preview-decode.sh: rest-row generation failed"; exit 1; }
for i in $(seq 0 49); do
    cp "$photos/seed$((i % 2)).jpg" "$photos/s$i.jpg" || exit 1
    cp "$photos/thumb.png" "$photos/t$i.png" || exit 1
done
cp "$photos/thumb.png" "$photos/t50.png" || exit 1

# Quick Look's three: 600x400 pixels exiv2 marks RightTop (EXIF 6), since magick writes no EXIF block; a banner; a PNG smaller than any box.
magick -size 600x400 gradient:white-black "$photos/portrait.jpg" \
    && exiv2 -M"set Exif.Image.Orientation Short 6" "$photos/portrait.jpg" \
    || { echo "preview-decode.sh: portrait generation failed"; exit 1; }
[ "$(magick identify -format '%[orientation]' "$photos/portrait.jpg")" = RightTop ] \
    || { echo "preview-decode.sh: the portrait fixture carries no EXIF turn"; exit 1; }
magick -size 3000x100 xc:gray60 "$photos/banner.png" \
    || { echo "preview-decode.sh: banner generation failed"; exit 1; }
magick -size 120x68 xc:gray40 "$photos/small.png" \
    || { echo "preview-decode.sh: small fixture generation failed"; exit 1; }
# The interim's own cache files: the small one draws at the original's pixels, the large one at 256 wide.
cp "$photos/small.png" "$photos/smallcache.png" \
    || { echo "preview-decode.sh: small cache generation failed"; exit 1; }

# Sample input: 'OPEN|t12.png' is a cache file, 'OPEN|s12.jpg' or 'OPEN|big.png' an original, 'CREATE|sentinel-rest' a phase boundary.
inotifywait -m -e open -e create --format '%e|%f' "$photos" > "$watchlog" 2>&1 &
watcher=$!

( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root" \
    XDG_CONFIG_HOME="$test_root/.config" XDG_STATE_HOME="$test_root/.local/state" XDG_CACHE_HOME="$test_root/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    PREVIEW_UI="$PWD/ui" PREVIEW_PHOTOS="$photos" \
    timeout 120 qs -p "$config_dir" > "$log" 2>&1 )
status=$?
# The watch outlives qs by a breath so its last events flush before it is read.
sleep 1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

if grep -q 'PREVIEW FAIL' "$log" || ! grep -q 'PREVIEW DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'PREVIEW FAIL' "$log" | head -1) (log $log)"
else
    # Sample input, one inotifywait line per event: 'OPEN|t0.png' is the first swept row's cache file, 'OPEN|t50.png' the rest row's, and 'CREATE|sentinel-rest' opens the rest window once the sweep one closes.
    got_sweep=0; got_rest=0; got_done=0; phase=0
    sweep_t0=0; sweep_other=0; sweep_other_names=""; rest_big=0; rest_cache=0; rest_sweep=0
    events=""; name=""
    while IFS='|' read -r events name || [ -n "$events" ]; do
        case "$events" in
        *CREATE*)
            if [ "$name" = "sentinel-sweep" ]; then phase=1; got_sweep=1
            elif [ "$name" = "sentinel-rest" ]; then [ "$phase" -eq 1 ] && phase=2; got_rest=1
            elif [ "$name" = "sentinel-done" ]; then [ "$phase" -eq 2 ] && phase=3; got_done=1
            fi
            ;;
        *OPEN*)
            # e80 loads a lone move at once: the sweep starts idle, so it loads t0.png only; repeats trail. One load opens t50.png rest_cache times, so t0.png may open at most that often.
            if [ "$phase" -eq 1 ]; then
                case "$name" in
                sentinel-*) ;;
                t0.png) sweep_t0=$((sweep_t0 + 1)) ;;
                *) sweep_other=$((sweep_other + 1)); [ "$sweep_other" -le 3 ] && sweep_other_names="$sweep_other_names $name" ;;
                esac
            elif [ "$phase" -eq 2 ]; then
                case "$name" in
                big.png) rest_big=$((rest_big + 1)) ;;
                t50.png) rest_cache=$((rest_cache + 1)) ;;
                s*.jpg) rest_sweep=$((rest_sweep + 1)) ;;
                esac
            fi
            ;;
        esac
    done < "$watchlog"
    if [ "$got_sweep" != 1 ] || [ "$got_rest" != 1 ] || [ "$got_done" != 1 ]; then
        bad "a phase sentinel never arrived (sweep=$got_sweep rest=$got_rest done=$got_done) (log $log)"
    else
        if [ "$sweep_other" -ne 0 ]; then
            bad "the sweep opened other row(s):$sweep_other_names besides t0.png (log $log)"
        elif [ "$sweep_t0" -eq 0 ]; then
            bad "the sweep opened no file, want the first row t0.png (log $log)"
        elif [ "$rest_cache" -ge 1 ] && [ "$sweep_t0" -gt "$rest_cache" ]; then
            bad "the sweep opened t0.png $sweep_t0 time(s), more than one load opens t50.png $rest_cache time(s) (log $log)"
        else
            ok "the sweep opened only the first row t0.png $sweep_t0 time(s), within one load"
        fi
        if [ "$rest_cache" -ge 1 ]; then
            ok "a rest drew the rested row's cache file"
        else
            bad "the rest never opened t50.png, so the column drew nothing of the row (log $log)"
        fi
        if [ "$rest_big" -eq 0 ] && [ "$rest_sweep" -eq 0 ]; then
            ok "and opened no original, the way v0.3.4 drew the column"
        else
            bad "the rest opened big.png $rest_big time(s) and sweep rows $rest_sweep time(s) (log $log)"
        fi
    fi
    # Sample input: 'PREVIEW QL portrait decoded=400x600 drawn=314x471'; Qt decodes a turned photo whole when its stored size fits the box.
    portrait=$(sed -n 's/.*PREVIEW QL portrait decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$portrait" in
        "400x600 314x471") ok "Quick Look draws an EXIF-turned photo upright at the exact fit, 314x471" ;;
        *) bad "Quick Look drew the portrait as '$portrait', not 400x600 upright drawn at 314x471 (log $log)" ;;
    esac
    # 3000x100 at the box's width is 754x25; Fit decoded the covering 14130x471 instead.
    banner=$(sed -n 's/.*PREVIEW QL banner decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$banner" in
        "754x25 754x25") ok "and decodes a 3000x100 banner at the exact fit, 754x25" ;;
        *) bad "Quick Look drew the banner as '$banner', not 754x25 decoded and drawn (log $log)" ;;
    esac
    small=$(sed -n 's/.*PREVIEW QL small decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$small" in
        "120x68 120x68") ok "and a 120x68 PNG at its own size, never enlarged" ;;
        *) bad "Quick Look drew the small PNG as '$small', not 120x68 (log $log)" ;;
    esac
    # The interim draws the cache file under the full decode within a pixel, adding no open.
    im_line() { grep -a -n "CREATE|sentinel-$1" "$watchlog" | head -1 | cut -d: -f1; }
    rect_ok() { IFS=, read -r -a a <<<"$1"; IFS=, read -r -a b <<<"$2"; [ "${#a[@]}" -eq 4 ] && [ "${#b[@]}" -eq 4 ] || return 1; for i in 0 1 2 3; do d=$((a[i]-b[i])); [ "${d#-}" -le 1 ] || return 1; done; }
    for spec in "small small.png smallcache.png" "large seed0.jpg thumb.png"; do
        set -- $spec
        label=$1; orig=$2; cache=$3
        # Sample input: 'PREVIEW INTERIM small irect=317,201,120,68 frect=317,201,120,68'
        line=$(grep -a "PREVIEW INTERIM $label " "$log" | head -1)
        irect=$(printf '%s' "$line" | sed -n 's/.* irect=\([0-9,]*\).*/\1/p')
        frect=$(printf '%s' "$line" | sed -n 's/.* frect=\([0-9,]*\).*/\1/p')
        if [ -z "$irect" ] || [ -z "$frect" ]; then
            bad "the interim never reported $label (log $log)"
            continue
        fi
        if rect_ok "$irect" "$frect"; then
            ok "the $label interim lands on the final's rect ($irect)"
        else
            bad "the $label interim drew $irect against the final $frect (log $log)"
        fi
        if grep -a -q "PREVIEW INTERIMSTACK $label ok" "$log"; then
            ok "the $label interim draws above the ground and below the final picture"
        else
            bad "the $label interim is not stacked between the ground and the final picture (log $log)"
        fi
        s0=$(im_line "istart-$label"); s1=$(im_line "iend-$label")
        if [ -z "$s0" ] || [ -z "$s1" ]; then
            bad "an interim sentinel never arrived for $label (log $log)"
            continue
        fi
        oopens=$(sed -n "${s0},${s1}p" "$watchlog" | grep -c "^OPEN|$orig\$")
        copens=$(sed -n "${s0},${s1}p" "$watchlog" | grep -c "^OPEN|$cache\$")
        if [ "$oopens" -eq 1 ]; then
            ok "and opened its original once, the interim adding none"
        else
            bad "the $label original opened $oopens time(s), want exactly 1 (log $log)"
        fi
        if [ "$copens" -eq 1 ]; then
            ok "and drew its cache file"
        else
            bad "the $label interim opened $cache $copens time(s), want exactly 1 (log $log)"
        fi
    done
    # e81f-r3: the interim meta-row guards, one PREVIEW GUARD line each.
    if grep -a -q "PREVIEW GUARD1 PASS" "$log"; then
        ok "the interim refuses a meta reply for a row that drifted onto another file"
    else
        bad "guard 1 did not pass: a drifted row's reply must not size the interim (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD2 PASS" "$log"; then
        ok "a drifted capture re-asks at the cursor row and takes that reply"
    else
        bad "guard 2 did not pass: the ask must move to the cursor row (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD3 PASS" "$log"; then
        ok "no row naming the file means no ask and no interim sizing"
    else
        bad "guard 3 did not pass: nothing may be asked when no row names the file (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD4 PASS" "$log"; then
        ok "the captured row keeps the ask when the cursor sits elsewhere"
    else
        bad "guard 4 did not pass: the ask must stay at the captured row (log $log)"
    fi
fi

printf 'preview-decode: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
if [ "$fail" -ne 0 ]; then
    grep -a -E 'TypeError|ReferenceError|ERROR|INTERIM|GUARD' "$log" | head -20
fi
[ "$fail" -eq 0 ]
