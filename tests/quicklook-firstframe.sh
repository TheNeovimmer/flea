#!/usr/bin/env bash
# Space on a small Markdown file draws a card that already holds its first block: no empty-card frame, content in frame 1.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-firstframe: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-quicklook-firstframe-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture} || exit 1
ln -s "$(readlink -m ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
cp tests/quicklook-firstframe.qml "$test_root/config/shell.qml" || exit 1
# A README-sized document: headings, paragraphs, a list, a fence, a quote and a table, well under the 64 KiB worker threshold.
cat > "$test_root/fixture/notes.md" <<'DOC'
# Quick Look notes

A paragraph with `inline code`, **bold** text and a [link](https://example.invalid/guide) that wraps across the card.

## Install

1. Build the tree.
2. Run the suite.
3. Read the log.

- first item with some words
- second item with some more words

```sh
cargo build --release
./tests/run-all.sh
```

> A quoted paragraph that says something worth reading twice.

| Name | Value |
| :--- | :--- |
| rows | 3 |
| columns | 2 |

## Notes

Another paragraph with enough words to take a second line in a narrow frame, so the first screen holds real text.
DOC
printf 'plain\n' > "$test_root/fixture/zzz.txt"
cycles=10
failures=0
for leg in reduced motion; do
    leg_root="$test_root/$leg"
    mkdir -p "$leg_root"/{home,state/flea,cache,runtime} || exit 1
    chmod 700 "$leg_root/runtime" || exit 1
    printf '{}\n' > "$leg_root/state/flea/ui.json"
    reduced=""
    [ "$leg" = reduced ] && reduced=1
    log="$leg_root/run.log"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
        HOME="$leg_root/home" XDG_STATE_HOME="$leg_root/state" XDG_CACHE_HOME="$leg_root/cache" \
        XDG_RUNTIME_DIR="$leg_root/runtime" FLEA_BIN="$PWD/target/debug/flea" FLEA_PATH="$test_root/fixture" \
        FLEA_REDUCED_MOTION="$reduced" QLFF_UI="$PWD/ui" QLFF_DIR="$test_root/fixture" QLFF_NAME=notes.md QLFF_CYCLES="$cycles" QLFF_MODE="${QLFF_MODE:-call}" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ 90 "$test_root/config" "$log" 2> "$leg_root/bus.log" ) 2>/dev/null
    status=$?
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-firstframe-$leg.log" 2>/dev/null
    grep -a 'QLFF \(CYCLE\|FAIL\|DONE\)' "$log" | sed "s/^/$leg: /"
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'QLFF DONE' "$log")" -ne 1 ] \
        || [ "$(grep -ac 'QLFF CYCLE' "$log")" -ne "$cycles" ] || grep -aqE 'QLFF FAIL|TypeError|ReferenceError' "$log"; then
        printf 'FAIL quicklook-firstframe: %s leg did not hold (qs exit %s)\n' "$leg" "$status"
        failures=$((failures + 1))
    fi
done
printf 'quicklook-firstframe: %s cycles x 2 legs, %s failed\n' "$cycles" "$failures"
[ "$failures" -eq 0 ]
