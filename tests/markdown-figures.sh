#!/usr/bin/env bash
# flea --figure-helper through the debug binary: the ten formulas and six
# diagram kinds render, the malformed pair answers error, the hostile trio
# never reaches an SVG, the oversize source is refused, EOF ends the helper
# at 0, and a missing engine exits 127 with one stderr line.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

fleabin="$PWD/target/debug/flea"
[ -x "$fleabin" ] || { echo "markdown-figures.sh: no debug binary at $fleabin, run cargo build first"; exit 1; }
qjs="$PWD/.superpowers/tools/qjs"
[ -f "$qjs" ] || { echo "markdown-figures.sh: no qjs at $qjs"; exit 1; }

test_root="$FIXTURE_ROOT/flea-markdown-figures-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

# The jail assumes Arch's merged-/usr loader layout, so on a box whose
# bwrap cannot run anything (this Debian one included) the jailed path is
# skipped loudly and the same requests drive qjs direct, the way
# src/backend/sandboxprobe.rs skips rather than fails there.
probe_out=$(printf '%s\n' '{"id":1,"kind":"math","source":"x^2","display":false,"theme":{"bg":"#101315","fg":"#c0caf5"}}' | FLEA_QJS="$qjs" "$fleabin" --figure-helper 2>/dev/null)
if printf '%s' "$probe_out" | grep -q '"id":1'; then
    engine=("$fleabin" --figure-helper)
    echo "markdown-figures.sh: driving the jailed helper"
else
    engine=("$qjs" "$PWD/ui/vendor/figure-helper.mjs")
    echo "markdown-figures.sh: SKIP the bwrap jail cannot run here, driving qjs direct"
fi

# One python driver builds every request, so the shell never quotes a formula.
cat > "$test_root/drive.py" <<'EOF'
import json, subprocess, sys
import re
prog, arg, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
# xmlns is a namespace, never a fetch, so it is stripped before the check.
def clean(svg):
    return re.sub(r'xmlns(?::\w+)?="[^"]*"', "", svg)
theme = {"bg": "#101315", "fg": "#c0caf5", "accent": "#7aa2f7", "font": "monospace", "bodyPx": 14}
maths = ["\\frac{a}{b}", "\\int_0^1 x^2\\,dx", "\\sum_{n=1}^{\\infty}\\frac{1}{n^2}",
    "\\begin{matrix}a&b\\\\c&d\\end{matrix}", "\\begin{aligned}x&=1\\\\y&=2\\end{aligned}",
    "x^2", "\\sqrt{2}", "\\alpha+\\beta=\\gamma",
    "\\lim_{x\\to0}\\frac{\\sin x}{x}", "\\binom{n}{k}=\\frac{n!}{k!(n-k)!}"]
diags = ["flowchart TD\n    A --> B", "sequenceDiagram\n    A->>B: hi",
    "stateDiagram-v2\n    A --> B", "classDiagram\n    A <|-- B",
    "erDiagram\n    A ||--|| B : has", "xychart-beta\n    x-axis [a, b]\n    bar [1, 2]"]
# Sample input: {"id":1,"kind":"math","source":"\\frac{a}{b}","display":true,"theme":{...}}.
reqs = []
for i, m in enumerate(maths):
    reqs.append({"id": 10 + i, "kind": "math", "source": m, "display": True, "theme": theme})
for i, d in enumerate(diags):
    reqs.append({"id": 20 + i, "kind": "mermaid", "source": d, "display": True, "theme": theme})
# The malformed pair, then a good request proving the loop survived both.
reqs.append({"id": 30, "kind": "math", "source": "\\frac{unclosed", "display": True, "theme": theme})
reqs.append({"id": 31, "kind": "mermaid", "source": "not a diagram {{{", "display": True, "theme": theme})
reqs.append({"id": 32, "kind": "math", "source": "x^2", "display": False, "theme": theme})
# The hostile trio: two formulas that must fail, one diagram unwrapped to no link.
reqs.append({"id": 40, "kind": "math", "source": "\\href{http://127.0.0.1:18037/x}{click}", "display": True, "theme": theme})
reqs.append({"id": 41, "kind": "math", "source": "\\url{http://127.0.0.1:18037/y}", "display": True, "theme": theme})
reqs.append({"id": 42, "kind": "mermaid", "source": "flowchart TD\n    A --> B\n    click A href \"http://127.0.0.1:18037/evil\"", "display": True, "theme": theme})
big = "flowchart TD\n" + "A-->B\n" * 8000
reqs.append({"id": 43, "kind": "mermaid", "source": big, "display": True, "theme": theme})
body = "".join(json.dumps(r) + "\n" for r in reqs[:3])
# A line that is not JSON at all: it answers id 0 and the loop survives it.
body += "this is not json\n"
body += "".join(json.dumps(r) + "\n" for r in reqs[3:])
p = subprocess.run([prog, arg], input=body, capture_output=True, text=True, timeout=300)
lines = [json.loads(l) for l in p.stdout.splitlines()]
by_id = {a["id"]: a for a in lines}
fails = []
def check(cond, why):
    print(("PASS " if cond else "FAIL ") + why)
    if not cond:
        fails.append(why)
# Every request is answered exactly once, by its own id, beside the id 0
# answer the non-JSON line earns.
check(sorted(k for k in by_id if k != 0) == sorted(r["id"] for r in reqs), "every request answered once under its own id")
check(p.returncode == 0, "EOF ends the helper with exit 0")
check(p.stderr == "", "a clean run writes nothing on stderr")
forbidden = ["http:", "https:", "@import", "<script", "<image", "foreignObject", "127.0.0.1"]
for i in range(10):
    a = by_id.get(10 + i, {})
    svg = a.get("svg", "")
    check(svg.startswith("<svg"), "formula %d renders an svg" % i)
    check(all(w not in clean(svg) for w in forbidden), "formula %d passes checkSafe" % i)
for i in range(6):
    a = by_id.get(20 + i, {})
    svg = a.get("svg", "")
    check(svg.startswith("<svg"), "diagram %d renders an svg" % i)
    check(all(w not in clean(svg) for w in forbidden), "diagram %d passes checkSafe" % i)
check("error" in by_id.get(30, {}), "the malformed formula answers error")
check("error" in by_id.get(31, {}), "the malformed diagram answers error")
check("error" in by_id.get(0, {}), "a line that is not JSON answers error under id 0")
check(by_id.get(32, {}).get("svg", "").startswith("<svg"), "the loop survives the malformed pair")
check("error" in by_id.get(40, {}), "the hostile href never reaches an svg")
check("error" in by_id.get(41, {}), "the hostile url never reaches an svg")
click = by_id.get(42, {}).get("svg", "")
check(click.startswith("<svg") and "127.0.0.1" not in click, "the hostile click unwraps to no link")
check(by_id.get(43, {}).get("error", "") == "diagram over 32 KiB", "the oversize source is refused")
if not fails:
    open(outdir + "/node-theme.json", "w").write(json.dumps(theme))
    open(outdir + "/node-expected.json", "w").write(json.dumps({"frac": by_id[10]["svg"], "flow": by_id[20]["svg"]}))
print("DONE failures=%d" % len(fails))
sys.exit(1 if fails else 0)
EOF
if ! python3 "$test_root/drive.py" "${engine[@]}" "$test_root"; then
    echo "markdown-figures.sh: the helper run failed"
    exit 1
fi

# A missing engine refuses with 127 and one stderr line, running nothing unsandboxed.
missing_out=$(FLEA_QJS="$test_root/no-such-qjs" "$fleabin" --figure-helper < /dev/null 2>&1)
missing_rc=$?
[ "$missing_rc" -eq 127 ] || { echo "markdown-figures.sh: FAIL missing qjs exited $missing_rc, want 127"; exit 1; }
[ "$(printf '%s\n' "$missing_out" | wc -l)" -eq 1 ] || { echo "markdown-figures.sh: FAIL missing qjs printed $(printf '%s\n' "$missing_out" | wc -l) lines, want 1"; exit 1; }
echo "PASS missing qjs exits 127 with one stderr line"

# Byte identity against node, the engine the bundles were built for. Loud skip when absent.
if ! command -v node >/dev/null; then
    echo "markdown-figures.sh: SKIP node is absent, so the byte-identity check did not run"
    echo "MARKDOWN_FIGURES DONE failures=0"
    exit 0
fi
cat > "$test_root/identity.mjs" <<'EOF'
import { readFileSync, writeFileSync } from "node:fs";
import { renderFigure } from "/PLACEHOLDER/ui/js/FigureWorker.mjs";
import { texToSvg } from "/PLACEHOLDER/ui/vendor/math.mjs";
import { mermaidToSvg } from "/PLACEHOLDER/ui/vendor/mermaid.mjs";
const theme = JSON.parse(readFileSync(process.argv[2], "utf8"));
const frac = renderFigure("math", "\\frac{a}{b}", true, theme, { texToSvg });
let flow = renderFigure("mermaid", "flowchart TD\n    A --> B", true, theme, { mermaidToSvg });
if (flow && flow.then)
    flow = await flow;
writeFileSync(process.argv[3], JSON.stringify({ frac, flow }));
EOF
sed -i "s#/PLACEHOLDER#$PWD#" "$test_root/identity.mjs"
node "$test_root/identity.mjs" "$test_root/node-theme.json" "$test_root/node-actual.json" || { echo "markdown-figures.sh: FAIL node could not render"; exit 1; }
python3 - "$test_root/node-expected.json" "$test_root/node-actual.json" <<'EOF'
import json, sys
want = json.load(open(sys.argv[1]))
got = json.load(open(sys.argv[2]))
assert want == got, "qjs and node disagree on rendered bytes"
print("PASS qjs renders the bundles byte-identical to node")
EOF

# FigureService against the real helper: cache, idle exit, timeout restart,
# the 127 latch and the fence. Loud skip where qs is absent.
if ! command -v qs >/dev/null; then
    echo "markdown-figures.sh: SKIP qs is absent, so the FigureService suite did not run"
    echo "MARKDOWN_FIGURES DONE failures=0"
    exit 0
fi
mkdir -p "$test_root/qsconfig" || exit 1
ln -s "$PWD/ui" "$test_root/qsconfig/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/qsconfig/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/qsconfig/Ui" || exit 1
cp tests/markdown-figures.qml "$test_root/qsconfig/shell.qml" || exit 1
mkdir -p "$test_root/stubbin" || exit 1
printf 'answer\n' > "$test_root/phase" || exit 1
# The service runs FLEA_BIN or "flea": with FLEA_BIN unset the stub answers,
# hangs or refuses per the phase file, and execs the real binary to answer.
cat > "$test_root/stubbin/flea" <<EOF
#!/bin/sh
if [ "\$1" = "--figure-helper" ]; then
    phase=\$(cat "$test_root/phase" 2>/dev/null)
    case "\$phase" in
        hang) sleep 30 ;;
        refused) echo "flea: stub has no engine" >&2; exit 127 ;;
        *) exec "$fleabin" --figure-helper ;;
    esac
fi
echo "stub flea: unexpected argv \$*" >&2
exit 2
EOF
chmod +x "$test_root/stubbin/flea" || exit 1
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_BIN \
    HOME="$test_root" XDG_STATE_HOME="$test_root" XDG_CACHE_HOME="$test_root" \
    XDG_RUNTIME_DIR="$test_root" FLEA_QJS="$qjs" FLEA_FIG_REAL="$fleabin" \
    FLEA_FIG_PHASE_FILE="$test_root/phase" PATH="$test_root/stubbin:$PATH" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 150 qs -p "$test_root/qsconfig" 2>&1 ) 2>/dev/null )
qs_status=$?
pass_count=$(printf '%s\n' "$output" | grep -c 'MARKDOWN_FIGURES PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'MARKDOWN_FIGURES FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'MARKDOWN_FIGURES DONE')
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS lines\n' "$done_count"
    verdict=1
fi
if [ "$fail_count" -ne 0 ]; then
    printf 'FAIL %s FigureService check(s) failed\n' "$fail_count"
    verdict=1
fi
if [ "$pass_count" -lt 10 ]; then
    printf 'FAIL only %s PASS lines, want at least 10 (answers, cache, idle, timeout, latch, fence)\n' "$pass_count"
    verdict=1
fi
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the FigureService harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output" | grep -a 'MARKDOWN_FIGURES FAIL' | head -30
    printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|RangeError|ERROR' | head -6
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MARKDOWN_FIGURES DONE.*'
echo "MARKDOWN_FIGURES DONE failures=0"
