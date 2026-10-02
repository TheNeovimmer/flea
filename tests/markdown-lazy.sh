#!/usr/bin/env bash
# The lazy-draw gate for rendered Markdown: a generated 1 MiB README (headings,
# paragraphs, lists, tables, fences) must parse off the UI thread and open with
# no more than the visible blocks plus the cache instantiated.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-lazy.sh: qs is not installed, cannot render the preview"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-lazy-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-lazy.qml "$test_root/config/shell.qml" || exit 1

# 2500 sections of six blocks each: about 600 KiB, about 15000 top-level
# blocks, so a whole-document build would dwarf the visible window.
python3 - "$test_root/notes.md" <<'EOF'
import sys
dest = sys.argv[1]
lines = []
for s in range(2500):
    lines.append(f"## Section {s}")
    lines.append("")
    lines.append(f"Paragraph {s} carries enough words to wrap a couple of lines in the frame.")
    lines.append("")
    lines.append(f"- item {s} alpha")
    lines.append(f"- item {s} beta")
    lines.append("")
    lines.append("| Kind | Asks for |")
    lines.append("| :--- | :--- |")
    lines.append(f"| rows {s} | the cursor |")
    lines.append("")
    lines.append("```js")
    lines.append(f"var section{s} = true;")
    lines.append("```")
    lines.append("")
with open(dest, "w") as f:
    f.write("\n".join(lines) + "\n")
print("readme bytes:", sum(len(l) + 1 for l in lines))
EOF
[ "$(stat -c %s "$test_root/notes.md")" -gt 524288 ] || { echo "FAIL the README fixture is too small"; exit 1; }

output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

if printf '%s\n' "$output" | grep -q 'MARKDOWN_LAZY FAIL'; then
    printf 'FAIL the lazy harness refused its fixture\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_LAZY|ERROR' | head -10
    exit 1
fi
line=$(printf '%s\n' "$output" | grep -aE 'MARKDOWN_LAZY blocks=' | head -1)
if [ -z "$line" ]; then
    printf 'FAIL the lazy harness never reported (no live preview ran)\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_LAZY|ERROR|error' | head -20
    exit 1
fi
blocks=$(printf '%s\n' "$line" | grep -aoE 'blocks=[0-9]+' | grep -aoE '[0-9]+')
delegates=$(printf '%s\n' "$line" | grep -aoE 'delegates=[0-9]+' | grep -aoE '[0-9]+')
offthread=$(printf '%s\n' "$line" | grep -aoE 'offthread=[a-z]+' | cut -d= -f2)
[ "$offthread" = "true" ] || { echo "FAIL the parse never left the UI thread"; exit 1; }
[ "$blocks" -ge 800 ] || { echo "FAIL only $blocks blocks, the fixture is no test"; exit 1; }
[ "$delegates" -le 150 ] || { echo "FAIL $delegates delegates for $blocks blocks, nothing is lazy"; exit 1; }
[ "$delegates" -lt "$((blocks / 4))" ] || { echo "FAIL $delegates delegates approach $blocks blocks"; exit 1; }
printf 'PASS %s blocks draw through %s delegates, parsed off thread\n' "$blocks" "$delegates"
