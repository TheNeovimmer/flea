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
cat > "$test_root/fixture/a-notes.md" <<'DOC'
# a-notes: Quick Look notes

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
printf '# d-small\n\nA second small document, so the held key has two rows to sweep.\n' > "$test_root/fixture/d-small.md"
# A 1 MiB and a 300 KB document made of ordinary blocks, past the 64 KiB worker threshold and under the 1 MiB refusal.
chunk=$'## Section\n\nA paragraph with `code`, **bold** and a [link](https://example.invalid) that runs long enough to wrap in a narrow card.\n\n- item one\n- item two\n\n'
{ printf '# b-big\n\n'; yes "$chunk" | head -c 1040000; } > "$test_root/fixture/b-big.md" 2>/dev/null
{ printf '# c-mid\n\n'; yes "$chunk" | head -c 300000; } > "$test_root/fixture/c-mid.md" 2>/dev/null
# A named pipe named like a document: a read of it never ends, so no read may touch it.
mkfifo "$test_root/fixture/e-pipe.md" || exit 1
printf 'plain\n' > "$test_root/fixture/zzz.txt"
repeat() { local out="$1" i; for ((i = 0; i < $2; i++)); do out+="${out:+,}$3"; done; printf '%s' "$out"; }
cycles=10
failures=0
legs=0
# run_leg LABEL STEPS CLASS REDUCED SWEEP TIMEOUT: one qs run over the steps, with the pane's storage class forced when CLASS is set.
run_leg() {
    local leg=$1 steps=$2 class=$3 reduced=$4 sweep=$5 limit=$6
    local leg_root="$test_root/$leg" log="$test_root/$leg/run.log" status
    mkdir -p "$leg_root"/{home,state/flea,cache,runtime} || exit 1
    chmod 700 "$leg_root/runtime" || exit 1
    printf '{}\n' > "$leg_root/state/flea/ui.json"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
        HOME="$leg_root/home" XDG_STATE_HOME="$leg_root/state" XDG_CACHE_HOME="$leg_root/cache" \
        XDG_RUNTIME_DIR="$leg_root/runtime" FLEA_BIN="$PWD/target/debug/flea" FLEA_PATH="$test_root/fixture" \
        FLEA_REDUCED_MOTION="$reduced" QLFF_UI="$PWD/ui" QLFF_DIR="$test_root/fixture" QLFF_STEPS="$steps" QLFF_CLASS="$class" QLFF_SWEEP="$sweep" QLFF_MODE="${QLFF_MODE:-call}" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ "$limit" "$test_root/config" "$log" 2> "$leg_root/bus.log" ) 2>/dev/null
    status=$?
    legs=$((legs + 1))
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-firstframe-$leg.log" 2>/dev/null
    grep -a 'QLFF \(STEP\|FAIL\|DONE\)' "$log" | sed "s/^/$leg: /"
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'QLFF DONE' "$log")" -ne 1 ] || grep -aqE 'QLFF FAIL|TypeError|ReferenceError' "$log"; then
        printf 'FAIL quicklook-firstframe: %s leg did not hold (qs exit %s)\n' "$leg" "$status"
        failures=$((failures + 1))
    fi
}
notes=$(repeat "" "$cycles" a-notes.md:inline)
run_leg reduced "$notes" "" 1 1 90
run_leg motion "$notes" "" "" 1 90
# Small then big then small, closed and reopened, then a move on the open card in both orders (small to big and big to small).
run_leg order "a-notes.md:inline,b-big.md:async,a-notes.md:inline,c-mid.md:async,d-small.md:inline,b-big.md:async,d-small.md:inline,a-notes.md:inline,b-big.md:async:move,c-mid.md:async:move,d-small.md:inline:move,c-mid.md:async:move,b-big.md:async:move,a-notes.md:inline:move" "" 1 "" 120
# A share, a phone and a USB drive read nothing ahead and nothing inside the key; the pane refuses past 256 KiB there, so only small files.
for class in network phone usb; do
    run_leg "class-$class" "a-notes.md:async,d-small.md:async" "$class" 1 "" 60
done
# A cursor resting on the pipe reads nothing: a read of it would never return, so this leg ends on its own timeout when the guard is gone.
run_leg pipe "e-pipe.md:rest" "" 1 "" 20
# A row that lists 900 bytes for a 300 KB file reads only up to the cap, and nothing is prepared from it.
run_leg capped "c-mid.md:capped" "" 1 "" 60
printf 'quicklook-firstframe: %s legs, %s failed\n' "$legs" "$failures"
[ "$failures" -eq 0 ]
