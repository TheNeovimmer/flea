#!/usr/bin/env bash
# The preview geometry gate (AGENTS.md "The preview swap"): every preview surface, kind and
# source-size class against one rule table, headless. Images draw at min(own size, aspect-fit),
# video posters fill the frame like the player, office thumbnails fill only at cache size, a PDF
# page contains. Prints one GEOMETRY line per cell and montages the cell grabs into a contact
# sheet a human looks at. Offscreen, so it needs neither the display nor the display lock.
set -u
cd "$(dirname "$0")/.." || exit 1

for tool in qs magick; do
    command -v "$tool" >/dev/null || { echo "preview-geometry.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-preview-geometry-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then
        printf 'preview-geometry: keeping %s\n' "$test_root"
        exit "$result"
    fi
    sandbox_remove "$test_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture" "$test_root/out" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-geometry.qml "$test_root/config/shell.qml" || exit 1

fixture="$test_root/fixture"
solid() { magick -size "$1" "xc:$2" "$fixture/$3" || { echo "preview-geometry.sh: fixture $3 failed"; exit 1; }; }
# Quick Look and original-leg images, exact pixel sizes.
solid 64x48 '#7aa2f7' img-64x48.png
solid 120x68 '#e0af68' img-120x68.png
solid 1920x1080 '#7aa2f7' img-1920x1080.png
solid 1080x1920 '#e0af68' img-1080x1920.png
solid 6000x4000 '#7aa2f7' img-6000x4000.png
# Cache-leg thumbnails, 256 px on the long side of the clip's aspect.
solid 256x144 '#3a8a5f' thumb-256x144.png
solid 144x256 '#3a8a5f' thumb-144x256.png
solid 256x171 '#3a8a5f' thumb-256x171.png
solid 256x256 '#3a8a5f' thumb-256x256.png
solid 256x192 '#3a8a5f' thumb-256x192.png
# Office embedded pictures: below cache size draws own-size, at it fills the frame.
solid 120x68 '#bb9af7' office-120x68.png
solid 181x256 '#bb9af7' office-181x256.png
# PDF pages, portrait and landscape, made the way case_preview makes its manual.pdf.
magick \( -size 400x560 xc:white -fill black -font Liberation-Sans -pointsize 40 -annotate +40+80 'PAGEONE' \) \
    "$fixture/doc-400x560.pdf" || { echo "preview-geometry.sh: portrait PDF fixture failed"; exit 1; }
magick \( -size 560x400 xc:white -fill black -font Liberation-Sans -pointsize 40 -annotate +40+80 'PAGEONE' \) \
    "$fixture/doc-560x400.pdf" || { echo "preview-geometry.sh: landscape PDF fixture failed"; exit 1; }

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    FLEA_PREVIEW_GEOMETRY_DIR="$fixture" FLEA_PREVIEW_GEOMETRY_OUT="$test_root/out" \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 180 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GEOMETRY columns-wide image 64x48 frame=758x473 rule=image-own-size ok".
cells=$(printf '%s\n' "$output" | grep -c '^.*GEOMETRY [a-z-]* [a-z]* [0-9x]* frame=')
ok_count=$(printf '%s\n' "$output" | grep -c ' rule=[a-z-]* ok$')
fail_count=$(printf '%s\n' "$output" | grep -c 'GEOMETRY FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'GEOMETRY DONE')
if [ "$cells" -ne 36 ] || [ "$ok_count" -ne 36 ] || [ "$fail_count" -ne 0 ] || [ "$done_count" -ne 1 ]; then
    printf 'FAIL the preview drew a picture at the wrong size: cells=%s ok=%s fail=%s\n' "$cells" "$ok_count" "$fail_count"
    printf '%s\n' "$output" | grep -aE 'GEOMETRY|ERROR|error' | head -40
    exit 1
fi
printf '%s\n' "$output" | grep -a 'GEOMETRY [a-z-]* [a-z]* [0-9x]* frame='

# The contact sheet: every cell grab in index order, titled by its own file name, for a human to look at.
mapfile -t grabs < <(ls "$test_root"/out/geometry-*.png | sort -V)
[ "${#grabs[@]}" -eq 36 ] || { echo "preview-geometry.sh: want 36 cell grabs, got ${#grabs[@]}"; exit 1; }
montage "${grabs[@]}" -tile 4x -geometry 320x240+4+4 -label '%f' "$test_root/sheet.png" \
    || { echo "preview-geometry.sh: the contact sheet failed"; exit 1; }
printf 'GEOMETRY cells=%s ok=%s fail=%s\n' "$cells" "$ok_count" "$fail_count"
printf 'GEOMETRY_SHEET %s\n' "$test_root/sheet.png"
