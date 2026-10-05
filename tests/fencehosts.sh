#!/usr/bin/env bash
# Every fence in a Markdown file opens as a code block in the preview column and in Quick Look, whatever the line endings, the size or where the entry came from.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session python3; do
    command -v "$tool" >/dev/null || { printf 'FAIL fencehosts: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-fencehosts-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state/flea,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
printf '{}\n' > "$test_root/state/flea/ui.json"
ln -s "$(readlink -m ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
cp tests/fencehosts.js "$test_root/config/fencehosts.js" || exit 1
cp tests/fencehosts.qml "$test_root/config/shell.qml" || exit 1
# The repo's own documents, then the synthetic fences: each shape in LF, CRLF and lone CR, and the 64 KiB line with a fence on each side of the head cut.
for doc in README.md CHANGELOG.md AGENTS.md docs/*.md; do
    cp "$doc" "$test_root/fixture/repo-$(basename "$doc")" || exit 1
done
# The two longest ordinary documents again with CRLF endings, as a file from another system holds them.
for doc in README.md CHANGELOG.md; do
    sed 's/$/\r/' "$doc" > "$test_root/fixture/repo-${doc%.md}-crlf.md" || exit 1
done
python3 - "$test_root/fixture" <<'PY' || exit 1
import sys
out = sys.argv[1]
TICK = "```toml\nk = 1\n```\n"
# Sample input: the key "tilde" is a document whose first fence is ~~~ with no language tag.
shapes = {
    "tick": "a\n\n```\ncode\n```\n\nb\n",
    "tick-lang": "a\n\n" + TICK + "\nb\n",
    "tilde": "a\n\n~~~\ncode\n~~~\n\nb\n",
    "tilde-lang": "a\n\n~~~rust\nfn x() {}\n~~~\n",
    "four": "a\n\n````\n```\ninner\n```\n````\n\nb\n",
    "list-item": "- item\n\n  ```\n  code\n  ```\n- two\n",
    "ordered-item": "1. ```sh\n   ls\n   ```\n2. next\n",
    "quote": "> a\n>\n> ```\n> code\n> ```\n",
    "indented": "text\n\n   ```\n   code\n   ```\n\nmore\n",
    "unclosed": "text\n\n```\ncode\nmore\n",
    "after-html": "<div>\nhi\n</div>\n```\ncode\n```\n",
    "after-table": "| a | b |\n|---|---|\n| 1 | 2 |\n```\ncode\n```\n",
    "tab-indented": "a\n\n\t```\n\tcode\n\t```\n",
    "first": "```\ncode\n```\ntail\n",
    "last": "head\n\n```\ncode\n```",
    "after-heading": "## h\n````ts\nx\n````\n",
    "blank-inside": "text\n\n```ts\n// c\n\n/**\n * x\n */\nexport x\n```\n\nafter\n",
}
ends = {"": "\n", "-crlf": "\r\n", "-cr": "\r"}
for name, text in shapes.items():
    for suffix, end in ends.items():
        open("%s/syn-%s%s.md" % (out, name, suffix), "w", newline="").write(text.replace("\n", end))
# A document of exactly size bytes: a fence at the top, one in the middle of the 96-block head, two just past it, then filler, then a last fence.
def sized(size, end):
    paras = ["# T", TICK.rstrip("\n")] + ["para %d" % i for i in range(94)] + [TICK.rstrip("\n")] * 2
    text = ""
    for p in paras:
        text += p.replace("\n", end) + end + end
    last = TICK.replace("\n", end)
    while len(text) + len(end) + len(last) + 25 < size:
        text += "filler paragraph line." + end + end
    pad = size - len(text) - len(end) - len(last)
    text += "x" * pad + end + last
    assert len(text.encode()) == size
    return text
# Each ending is its own base name, as the filler that reaches the size differs with the ending's width.
for size in (65535, 65537):
    for kind, end in (("lf", "\n"), ("crlf", "\r\n"), ("cr", "\r")):
        open("%s/syn-size%s-%d.md" % (out, kind, size), "w", newline="").write(sized(size, end))
PY
docs=$(cd "$test_root/fixture" && for f in *.md; do printf '%s|%s\n' "$f" "$(stat -c %s "$f")"; done)
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_RUNTIME_DIR="$test_root/runtime" \
    FENCEHOSTS_DOCS="$docs" FENCEHOSTS_DIR="$test_root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="$(qslog_rules)" \
    dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ 300 "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/fencehosts.log" 2>/dev/null
failures=0
grep -a 'FENCEHOSTS \(DOC\|FAIL\|DONE\)' "$log" | sed 's/^.*FENCEHOSTS /FENCEHOSTS /'
qslog_nullptr fencehosts < "$log" || failures=$((failures + 1))
qslog_crash fencehosts "$log" || failures=$((failures + 1))
total=$(printf '%s\n' "$docs" | grep -c .)
done_line=$(grep -a -m1 'FENCEHOSTS DONE' "$log")
if [ "$status" -ne 0 ] || [[ "$done_line" != *"docs=$total expected=$total failures=0" ]] || grep -aqE 'FENCEHOSTS FAIL|TypeError|ReferenceError' "$log"; then
    printf 'FAIL fencehosts: the hosts did not hold (qs exit %s)\n' "$status"
    failures=$((failures + 1))
fi
printf 'fencehosts: %s documents in 3 hosts, %s failed\n' "$total" "$failures"
[ "$failures" -eq 0 ]
