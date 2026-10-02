#!/usr/bin/env bash
# The real ui/PreviewMarkdown.qml over a figure fixture, grabbed offscreen: one
# flowchart, one math fence and one $$ display block draw figures, a malformed
# diagram draws the mono fallback, widths never exceed the text width, and no
# figure request leaves for the far block past the filler. With a qjs engine
# and a built flea binary present the real `flea --figure-helper` answers
# through the real FigureService (MODE=real, the class gate); otherwise a stub
# `flea` answers a canned 800x400 SVG (MODE=stub). Each good figure's rect must
# hold ink that is not the chrome surface.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-figures-render.sh: qs is not installed, cannot render the preview"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-figrender-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/stubbin" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-figures-render.js "$test_root/config/" || exit 1
cp tests/markdown-figures-render.qml "$test_root/config/shell.qml" || exit 1

# The class gate: with an engine and a built binary the real helper answers,
# so CI runs the real path (FigureService Process, helper answer, svg to
# Image); otherwise the stub below stands in and the mode is printed.
resolve_qjs() {
    if [ -n "${FLEA_QJS:-}" ] && [ "${FLEA_QJS#/}" != "${FLEA_QJS}" ] && [ -x "${FLEA_QJS}" ]; then
        printf '%s\n' "${FLEA_QJS}"
    elif command -v qjs >/dev/null 2>&1; then
        command -v qjs
    elif [ -x "$PWD/.superpowers/tools/qjs" ]; then
        printf '%s\n' "$PWD/.superpowers/tools/qjs"
    else
        return 1
    fi
}
fleabin=""
for cand in "$PWD/target/debug/flea" "$PWD/target/release/flea"; do
    if [ -x "$cand" ]; then fleabin="$cand"; break; fi
done
mode=stub
if qjs=$(resolve_qjs) && [ -n "$fleabin" ]; then
    mode=real
fi
printf 'MODE=%s\n' "$mode"

# The real helper resolves its UI tree from FLEA_UI, so the suite names this
# checkout's ui rather than inheriting whatever the caller exported.
export FLEA_UI="${FLEA_UI:-$PWD/ui}"
if [ "$mode" = real ]; then
# Sample input: {"id":1,"kind":"math","source":"x^2","display":false,"theme":{...}}.
helper_probe_out=$(printf '%s\n' '{"id":1,"kind":"math","source":"x^2","display":false,"theme":{"bg":"#101315","fg":"#c0caf5","accent":"#7aa2f7","font":"monospace","bodyPx":14}}' | FLEA_QJS="$qjs" "$fleabin" --figure-helper 2>&1)
if ! printf '%s\n' "$helper_probe_out" | grep -q '"svg"'; then
    printf 'FAIL the figure helper did not answer: %s\n' "$helper_probe_out"
    exit 1
fi
fi

if [ "$mode" = stub ]; then
# Sample input: {"id":3,"kind":"math","source":"\\frac{a}{b}","display":true,"theme":{...}}.
cat > "$test_root/stubbin/answer.py" <<'EOF'
import json, os, sys, time
svg = '<svg xmlns="http://www.w3.org/2000/svg" width="800" height="400"><rect width="800" height="400" fill="#7aa2f7"/></svg>'
logpath = os.environ.get("FLEA_FIG_REQ_LOG", "")
t0 = time.time()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except Exception as e:
        sys.stdout.write(json.dumps({"id": 0, "error": str(e)[:80]}) + "\n")
        sys.stdout.flush()
        continue
    rid = req.get("id", 0)
    src = str(req.get("source", ""))
    if logpath:
        with open(logpath, "a") as f:
            f.write("%.1f %s\n" % (time.time() - t0, src.replace("\n", "|")[:160]))
    if "not a diagram" in src:
        sys.stdout.write(json.dumps({"id": rid, "error": "mermaid render failed"}) + "\n")
    else:
        sys.stdout.write(json.dumps({"id": rid, "svg": svg}) + "\n")
    sys.stdout.flush()
EOF
cat > "$test_root/stubbin/flea" <<EOF
#!/bin/sh
if [ "\$1" = "--figure-helper" ]; then
    exec python3 "$test_root/stubbin/answer.py"
fi
echo "stub flea: unexpected argv \$*" >&2
exit 2
EOF
chmod +x "$test_root/stubbin/flea" || exit 1
fi

{
echo '# Figures'
echo ''
echo '```mermaid'
echo 'flowchart TD'
echo '    A --> B'
echo '```'
echo ''
echo '```math'
echo '\frac{a}{b}'
echo '```'
echo ''
echo '$$'
echo 'x^2'
echo '$$'
echo ''
echo '```mermaid'
echo 'not a diagram {{{'
echo '```'
echo ''
echo 'A paragraph with $x^2$ inline maths and `code`.'
echo ''
echo '```mermaid'
echo 'flowchart TD'
echo '    FAR --> AWAY'
echo '```'
} > "$test_root/notes.md"

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
if [ "$mode" = real ]; then
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIGURE_FIXTURE="$test_root/notes.md" \
    FLEA_FIG_MODE=real FLEA_BIN="$fleabin" FLEA_QJS="$qjs" FLEA_UI="$FLEA_UI" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
else
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_BIN \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIGURE_FIXTURE="$test_root/notes.md" \
    FLEA_FIG_MODE=stub FLEA_FIG_REQ_LOG="$test_root/requests.log" PATH="$test_root/stubbin:$PATH" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
fi

# Sample input, the verdict line: "  INFO qml: MARKDOWN_FIGRENDER PASS three figures, one mono fallback, widths fit, far figure unasked"
if [ "$(printf '%s\n' "$output" | grep -c 'MARKDOWN_FIGRENDER PASS')" -ne 1 ] || printf '%s\n' "$output" | grep -q 'MARKDOWN_FIGRENDER FAIL'; then
    printf 'FAIL the figure preview missed a check\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_FIGRENDER|FigureService|ERROR|error|flea:' | head -20
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the probe's.
# The QJSEngine connect line is a failure here, never filtered: an invalid
# nullptr connect at singleton creation would mean FigureService done never lands.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|invalid nullptr parameter' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the figure render harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
shot=$(ls "$test_root/runtime"/markdown-figrender-*.png 2>/dev/null | head -1)
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ] && [ -n "$shot" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS" || exit 1
    cp "$shot" "$FLEA_CI_SUITE_LOGS/markdown-figures-render.png" || exit 1
    printf 'shot %s\n' "$FLEA_CI_SUITE_LOGS/markdown-figures-render.png"
elif [ -n "$shot" ]; then
    printf 'shot %s\n' "$shot"
fi
# No figure request leaves for the far block past the filler. In stub mode the
# stub logs every source it is asked for, so the far source must never appear
# there while the near ones do. In real mode the settled delegates prove the
# near figures were asked and answered, and the missing far delegate proves it
# was never asked, so there is no log to grep.
if [ "$mode" = stub ]; then
for want in "flowchart TD" "frac{a}{b}" "x^2" "not a diagram"; do
    grep -qF "$want" "$test_root/requests.log" 2>/dev/null \
        || { printf 'FAIL the helper was never asked for %s\n' "$want"; exit 1; }
done
if grep -qF "FAR" "$test_root/requests.log" 2>/dev/null; then
    printf 'FAIL the far figure was asked for despite sitting past the cache\n'
    printf -- '--- requests.log ---\n'
    cat "$test_root/requests.log" 2>/dev/null | head -60
    printf 'request lines=%s far lines=%s\n' "$(wc -l < "$test_root/requests.log" 2>/dev/null)" "$(grep -cF 'FAR' "$test_root/requests.log" 2>/dev/null)"
    printf -- '--- qs output ---\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_FIGRENDER' | head -30
    exit 1
fi
fi
printf '%s\n' "$output" | grep -oE 'MARKDOWN_FIGRENDER (CHECK|far top=|x\^2 ink|PASS).*'
