#!/usr/bin/env bash
# Real rendered Markdown and Quick Look scroll behavior against the release boards.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-hunt.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/fixture"
ln -s "$PWD/ui" "$test_root/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/preview-hunt.qml "$test_root/config/shell.qml"
printf 'Hello preview.\n' > "$test_root/fixture/control.md"
printf '%s\n' '- [ ] todo' '- [x] done' > "$test_root/fixture/tasks.md"
printf '%s\n' 'Read [guide][g].' '' '```' 'code' '```' '' '[g]: https://example.com/guide' > "$test_root/fixture/reference.md"
printf '%s\n' '| Name |' '| --- |' '| **bold** |' > "$test_root/fixture/table.md"
printf '%s\n' '[guide](https://example.invalid/guide)' > "$test_root/fixture/theme.md"
printf '%s\n' '[http](http://example.invalid/http)' '' '[https](https://example.invalid/https)' '' '[mail](mailto:test@example.invalid)' '' '[relative](./other.md)' '' '[anchor](#heading)' > "$test_root/fixture/links.md"
printf 'Before disk edit.\n' > "$test_root/fixture/disk.md"
printf 'Before disk edit.\n' > "$test_root/fixture/disk-rename.md"
printf 'Before disk edit.\n' > "$test_root/fixture/disk-stale.md"
printf 'Other file.\n' > "$test_root/fixture/disk-stale-b.md"
# The parse-count fixtures: two files of different text, one of the second's text, and two past the worker threshold.
printf 'Alpha text.\n' > "$test_root/fixture/pc-a.md"
printf 'Beta text.\n' > "$test_root/fixture/pc-b.md"
printf 'Beta text.\n' > "$test_root/fixture/pc-c.md"
printf '![local](wide.png)\n' > "$test_root/fixture/local-image.md"
# Offscreen Qt has no platform URL service. Interpose only that native dispatch, with a positive control.
cc -shared -fPIC tests/markdown-link-spy.c -o "$test_root/link-spy.so" || exit 1
python3 - "$test_root/fixture" <<'PY'
from pathlib import Path
import struct, sys, zlib
root=Path(sys.argv[1])
for name in ('a','b'):
 (root/(name+'.md')).write_text('\n\n'.join(f'{name} paragraph {i}.' for i in range(100)))
(root/'long-list.md').write_text('\n'.join(f'- Item {i} with enough plain text to force the worker parse path.' for i in range(1500))+'\n')
(root/'long-table.md').write_text('| Name | Value |\n| --- | --- |\n'+'\n'.join(f'| Row {i} | plain table cell with enough text to require the parser worker |' for i in range(1200))+'\n')
def chunk(tag, body):
 return struct.pack('>I',len(body))+tag+body+struct.pack('>I',zlib.crc32(tag+body)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1200,600,8,2,0,0,0))
png+=chunk(b'IDAT',zlib.compress((b'\0'+b'\x40\x80\xc0'*1200)*600))+chunk(b'IEND',b'')
(root/'disk-scroll.md').write_text('\n\n'.join(f'scroll paragraph {i}.' for i in range(300))+'\n')
(root/'wide.png').write_bytes(png)
for name in ('alpha','beta'):
 (root/('pc-big-'+name[0]+'.md')).write_text('\n'.join(f'- {name} item {i} with enough plain text to force the worker parse path.' for i in range(1500))+'\n')
PY
failures=0
scenarios=(control tasks reference table scroll source-key size-key theme links disk disk-rename disk-scroll disk-stale local-image long-list long-table parse-quick parse-column parse-worker)
for scenario in "${scenarios[@]}"; do
    link_preload=""
    case "$scenario" in
        theme|links|disk|disk-rename|disk-scroll|disk-stale|local-image|long-list|long-table) cp tests/markdown-hunt.qml "$test_root/config/shell.qml" ;;
        parse-*) cp tests/markdown-parse-count.qml "$test_root/config/shell.qml" ;;
        *) cp tests/preview-hunt.qml "$test_root/config/shell.qml" ;;
    esac
    [ "$scenario" != links ] || link_preload="$test_root/link-spy.so"
    phase="$test_root/$scenario"
    mkdir -p "$phase"/{home,state,cache,data,runtime,tmp}
    chmod 700 "$phase/runtime"
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$phase/home" XDG_STATE_HOME="$phase/state" XDG_CONFIG_HOME="$phase/home/.config" \
        XDG_CACHE_HOME="$phase/cache" XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$phase/runtime" TMPDIR="$phase/tmp" \
        FLEA_BIN="$PWD/target/debug/flea" FLEA_PREVIEW_HUNT_CASE="$scenario" FLEA_PREVIEW_HUNT_DIR="$test_root/fixture" \
        LD_PRELOAD="$link_preload" FLEA_MARKDOWN_OPEN_LOG="$phase/open.log" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        timeout 15 qs -p "$test_root/config" 2>&1)
    code=$?
    printf 'PREVIEW_HUNT CASE %s exit=%s\n' "$scenario" "$code"
    printf '%s\n' "$output" | sed -n '/PREVIEW_HUNT/p'
    if [ "$code" -ne 0 ] || ! printf '%s\n' "$output" | grep -q 'PREVIEW_HUNT DONE.*0 failed'; then
        failures=$((failures+1))
        if ! printf '%s\n' "$output" | grep -q 'PREVIEW_HUNT DONE'; then
            echo 'FAIL preview hunt did not complete'
            printf '%s\n' "$output" | tail -8
        fi
    fi
    warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign' || true)
    if [ -n "$warnings" ]; then printf 'FAIL preview binding warning: %s\n' "$warnings"; failures=$((failures+1)); fi
    if [ "$scenario" = source-key ]; then
        if ! python3 - "$phase/state/flea/ui.json" <<'PY'
import json,sys
try:r=json.load(open(sys.argv[1]))
except (OSError,ValueError):sys.exit(1)
sys.exit(0 if r.get('preview',{}).get('markdownView')=='source' else 1)
PY
        then echo 'FAIL Source choice was not persisted for restart'; failures=$((failures+1)); fi
    fi
done
printf 'preview-hunt: %s phases, %s failed\n' "${#scenarios[@]}" "$failures"
[ "$failures" -eq 0 ]
