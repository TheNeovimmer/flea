#!/usr/bin/env bash
# Maths and Mermaid figures through the real ui/MarkdownFigure, grabbed
# offscreen and judged on pixel facts, with a hit-counting HTTP server proving
# no figure ever fetched anything.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-figures.sh: qs is not installed, cannot render figures"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "markdown-figures.sh: python3 is not installed, cannot count fetches"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-figures-$$"
sandbox_make "$test_root"
cleanup() {
    [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true
    sandbox_remove "$test_root"
}
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-figures.qml "$test_root/config/shell.qml" || exit 1
cp tests/markdown-figures-cases.js "$test_root/config/markdown-figures-cases.js" || exit 1

port=18037
cat > "$test_root/hitserver.py" <<EOF
import http.server
hits = [0]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/count":
            body = str(hits[0]).encode()
        else:
            hits[0] += 1
            body = b"ok"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
http.server.HTTPServer(("127.0.0.1", $port), H).serve_forever()
EOF
python3 "$test_root/hitserver.py" & server_pid=$!
for _ in $(seq 1 50); do
    if python3 -c "import socket;socket.create_connection(('127.0.0.1',$port),timeout=1).close()" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_FIG_PORT="$port" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 150 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
qs_status=$?

# Forensic grab for the report: the whole column in one frame.
# Copied whatever the verdict, so a red run still leaves its pixels behind.
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS" || exit 1
    if [ -f "$test_root/runtime/fig-col.png" ]; then
        cp "$test_root/runtime/fig-col.png" "$FLEA_CI_SUITE_LOGS/markdown-figures-col.png" || exit 1
        printf 'shot %s\n' "$FLEA_CI_SUITE_LOGS/markdown-figures-col.png"
    fi
fi

# Sample input, the verdict line: "  INFO qml: MARKDOWN_FIGURES DONE failures=0".
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
    printf 'FAIL %s figure check(s) failed\n' "$fail_count"
    verdict=1
fi
if [ "$pass_count" -lt 20 ]; then
    printf 'FAIL only %s PASS lines, want at least 20 (figures, fallbacks, thread, fetches)\n' "$pass_count"
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the probe's.
# The QML analyzer also mutters usedbeforedeclared over evaluated bundle text ("eval code" sites);
# that is minified third-party code identical to what node runs, never this tree, so only eval-code
# sites are excused and any such finding in a real file still fails.
platform_warning='This plugin does not support setting window masks'
eval_warning='eval code'
# Creating any WorkerScript logs one invalid-nullptr connect from inside
# Quickshell itself; the trivial round-trip probe proves it fires with no
# figure code involved, so it is the platform's, never the probe's.
connect_warning='invalid nullptr parameter'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning" | grep -vF "$eval_warning" | grep -vF "$connect_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the figures harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output" | grep -a 'MARKDOWN_FIGURES FAIL' | head -30
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_FIGURES (DONE|WEBENGINE|HOSTING|fetches|worker|pssKiB)' | head -12
    printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|RangeError|ERROR' | head -6
    printf '%s\n' "$output" | grep -a 'MARKDOWN_FIGURES pixels' | tail -4
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MARKDOWN_FIGURES DONE.*'
printf '%s\n' "$output" | grep -aE 'MARKDOWN_FIGURES (cold|lat|pssKiB|worker|HOSTING|WEBENGINE)' | head -40
printf '%s\n' "$output" | grep -a 'SENDSTORM' | head -4
