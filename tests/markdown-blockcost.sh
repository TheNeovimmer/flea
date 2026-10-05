#!/usr/bin/env bash
# Gate that a Markdown block builds only its own kind: no block holds another kind's parts, and every kind stays under its object count.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1

# The fixture's maths run holds two distinct formulas, one of them twice, so its drawn state is two pictures.
maths_drawn=2
kinds="run maths heading table list quote fence remote image images"
# The parts the probe can name (foreignParts in tests/markdown-blockcost.qml); any other name in a report is refused.
known_parts='Repeater|Column|Row|Rectangle|Image|MarkdownFigure|TextMetrics|Glyph'
# Object counts of one block on the shipped delegate, its ten inert Components included; the parts Loader adds 1 to a quote and 1 per list row, and a badge row adds its pictures.
limit_for() {
    case $1 in
        run|heading|fence) echo 14 ;;
        # A run with maths builds 10 objects per distinct formula (its figure holds two FontMetrics for a diagram's advances) on a base of 16, drawn: two formulas in the fixture.
        maths) echo 36 ;;
        table) echo 40 ;;
        list) echo 27 ;;
        quote) echo 18 ;;
        # The remote box draws its dashes as one Shape, whatever the pane width.
        remote) echo 20 ;;
        image) echo 15 ;;
        images) echo 20 ;;
    esac
}
# Parts each kind never draws, as an extended regex over the report's foreign list.
forbidden_for() {
    case $1 in
        run|heading) echo 'Repeater|Column|Row|Rectangle|Image|MarkdownFigure|TextMetrics|Glyph' ;;
        # A run with inline formulas builds one figure per distinct formula, and so its Repeater, Images and fallback Rectangle.
        maths) echo 'Column|Row|TextMetrics|Glyph' ;;
        table) echo 'Image|MarkdownFigure|TextMetrics|Glyph' ;;
        list) echo 'Rectangle|Image|MarkdownFigure|Glyph' ;;
        # A quote draws one bar per level, so it may hold a Repeater beside its Row and Rectangle.
        quote) echo 'Column|Image|MarkdownFigure|TextMetrics|Glyph' ;;
        fence) echo 'Repeater|Column|Row|Image|MarkdownFigure|TextMetrics|Glyph' ;;
        remote) echo 'Repeater|Rectangle|Image|MarkdownFigure|TextMetrics' ;;
        image) echo 'Repeater|Column|Row|Rectangle|MarkdownFigure|TextMetrics|Glyph' ;;
        images) echo 'Column|Row|Rectangle|MarkdownFigure|TextMetrics|Glyph' ;;
    esac
}

check_report() {
    local output=$1 kind line objects foreign limit
    for kind in $kinds; do
        # Sample input: MARKDOWN_BLOCKCOST kind=run objects=9 foreign=none drawn=0 parts={"MarkdownText":1}.
        line=$(printf '%s\n' "$output" | grep -aE "MARKDOWN_BLOCKCOST kind=$kind objects=" | head -1)
        if [ -z "$line" ]; then
            printf 'FAIL the harness never reported a %s block\n' "$kind"
            return 1
        fi
        objects=$(printf '%s\n' "$line" | grep -aoE 'objects=[0-9]*' | cut -d= -f2)
        foreign=$(printf '%s\n' "$line" | grep -aoE 'foreign=[A-Za-z+]+' | cut -d= -f2)
        case $objects in
            ''|*[!0-9]*) printf 'FAIL a %s block reported no object count: %s\n' "$kind" "$line"; return 1 ;;
        esac
        limit=$(limit_for "$kind")
        if [ "$objects" -gt "$limit" ]; then
            printf 'FAIL a %s block builds %s objects, the limit is %s\n' "$kind" "$objects" "$limit"
            return 1
        fi
        if [ "$kind" = maths ] && ! printf '%s\n' "$line" | grep -qE " drawn=$maths_drawn( |$)"; then
            printf 'FAIL the maths block did not draw its %s formulas: %s\n' "$maths_drawn" "$line"
            return 1
        fi
        if [ -z "$foreign" ]; then
            printf 'FAIL a %s block reported no part list: %s\n' "$kind" "$line"
            return 1
        fi
        if [ "$foreign" != none ] && printf '%s\n' "$foreign" | tr '+' '\n' | grep -qvxE "$known_parts"; then
            printf 'FAIL a %s block reported a part the probe never names: %s\n' "$kind" "$foreign"
            return 1
        fi
        if printf '%s\n' "$foreign" | tr '+' '\n' | grep -qxE "$(forbidden_for "$kind")"; then
            printf 'FAIL a %s block builds the parts of other kinds: %s\n' "$kind" "$foreign"
            return 1
        fi
    done
    printf 'PASS each block kind builds only its own parts within its object count\n'
}

# Controls: a report at every limit passes, and each kind is refused over its count, with a forbidden or unknown part, or with no count or part list.
control_report() {
    local kind
    for kind in $kinds; do
        printf 'MARKDOWN_BLOCKCOST kind=%s objects=%s foreign=none drawn=%s parts={}\n' "$kind" "$(limit_for "$kind")" "$maths_drawn"
    done
}
control_all=$(control_report)
check_report "$control_all" >/dev/null || { echo "FAIL the gate refused blocks at their limits"; exit 1; }
# A control passes only when check_report refuses the report with the branch's own message.
expect_refusal() {
    local report=$1 reason=$2 said
    if said=$(check_report "$report"); then
        printf 'FAIL the gate accepted a report it must refuse for: %s\n' "$reason"
        exit 1
    fi
    case $said in
        *"$reason"*) ;;
        *) printf 'FAIL the gate refused for another reason than "%s": %s\n' "$reason" "$said"; exit 1 ;;
    esac
}
for kind in $kinds; do
    limit=$(limit_for "$kind")
    part=$(forbidden_for "$kind" | cut -d'|' -f1)
    # The forbidden part trails a part the kind may hold, so a gate reading only the first name still fails.
    lead=$(printf '%s\n' "$known_parts" | tr '|' '\n' | grep -vxE "$(forbidden_for "$kind")" | head -1)
    # Run and heading forbid every known part, so there a second forbidden part leads; any name refuses those kinds.
    [ -n "$lead" ] || lead=$(forbidden_for "$kind" | cut -d'|' -f2)
    [ -n "$lead" ] || { echo "FAIL no part to lead the $kind control"; exit 1; }
    at="kind=$kind objects=$limit foreign=none"
    expect_refusal "$(printf '%s\n' "$control_all" | sed "s/$at/kind=$kind objects=$((limit + 1)) foreign=none/")" "objects, the limit is"
    expect_refusal "$(printf '%s\n' "$control_all" | sed "s/$at/kind=$kind objects=$limit foreign=$lead+$part/")" "builds the parts of other kinds"
    expect_refusal "$(printf '%s\n' "$control_all" | sed "s/$at/kind=$kind objects= foreign=none/")" "reported no object count"
    expect_refusal "$(printf '%s\n' "$control_all" | sed "s/$at/kind=$kind objects=$limit foreign= /")" "reported no part list"
    expect_refusal "$(printf '%s\n' "$control_all" | sed "s/$at/kind=$kind objects=$limit foreign=Loader/")" "a part the probe never names"
done
expect_refusal "$(printf '%s\n' "$control_all" | sed "s/kind=maths objects=$(limit_for maths) foreign=none drawn=$maths_drawn/kind=maths objects=$(limit_for maths) foreign=none drawn=0/")" "did not draw its"
printf 'ok the gate refuses every kind over its count, with a foreign or unknown part, or with no count or part list\n'

if ! command -v qs >/dev/null; then
    echo "markdown-blockcost.sh: qs is not installed, cannot build the blocks"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-blockcost-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/docs" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-blockcost.qml "$test_root/config/shell.qml" || exit 1

python3 - "$test_root/docs/kinds.png" <<'PY' || exit 1
import struct, sys, zlib
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x40\x80\xc0' * 8) * 8)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
# One block of every kind but the figure, whose picture arrives from a process and would change the count mid-census.
cat > "$test_root/docs/kinds.md" <<'MD'
# A heading

A paragraph with `code` and [a link](https://example.com/guide).

## A second heading

An inline formula $x^2$ in a line, then $y_1$, and $x^2$ again.

| Kind | Asks for |
| :--- | :--- |
| rows | the cursor |
| facts | the table |

1. First item
2. Second item

> A quoted line.

```js
var fenced = true;
```

![shot](https://cdn.example.com/shot.png)

![local](kinds.png)

<p align="center"><a href="https://example.com/a"><img src="kinds.png" alt="a"></a> <img src="kinds.png" alt="b" width="40"></p>
MD

# A stand-in figure helper: it answers each request line with a small SVG, so the formula in kinds.md draws.
mkdir -p "$test_root/stub" || exit 1
cat > "$test_root/stub/flea" <<'PY'
#!/usr/bin/env python3
import json, sys
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="2ex" height="2ex" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>'
for line in sys.stdin:
    # Sample input: {"id":3,"kind":"math","source":"x^2","display":false,"theme":{"bg":"#101315"}}.
    print(json.dumps({"id": json.loads(line)["id"], "svg": SVG}), flush=True)
PY
chmod +x "$test_root/stub/flea" || exit 1

# Sample input: '    readonly property int watchdogMs: 50000'; qs gets a margin past it so a stuck load names itself.
watchdog_ms=$(sed -n 's/.*readonly property int watchdogMs: *\([0-9][0-9]*\).*/\1/p' tests/markdown-blockcost.qml)
[ -n "$watchdog_ms" ] || { echo "markdown-blockcost.sh: watchdogMs not found in tests/markdown-blockcost.qml"; exit 1; }
probe_timeout_margin=10
probe_timeout=$((watchdog_ms / 1000 + probe_timeout_margin))
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BLOCKCOST_LIST="$test_root/docs/kinds.md" FLEA_BIN="$test_root/stub/flea" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout "$probe_timeout" qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

printf '%s\n' "$output" | qslog_nullptr 0 markdown-blockcost || exit 1
printf '%s\n' "$output" | grep -aE 'MARKDOWN_BLOCKCOST (doc|kind)=' | sed 's/ parts=.*//'
if printf '%s\n' "$output" | grep -q 'MARKDOWN_BLOCKCOST FAIL'; then
    printf 'FAIL the harness refused its fixture\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_BLOCKCOST|ERROR' | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -q 'MARKDOWN_BLOCKCOST DONE 1 documents' || { echo "FAIL the harness never finished"; exit 1; }
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF 'This plugin does not support setting window masks')
if [ -n "$warnings" ]; then
    printf 'FAIL the harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
check_report "$output"
