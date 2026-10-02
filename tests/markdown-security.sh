#!/usr/bin/env bash
# Render hostile Markdown through the preview and Text.MarkdownText; require a control GET and zero corpus requests.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-security.sh: qs is not installed, cannot render the preview"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "markdown-security.sh: python3 is not installed, cannot count hits"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-security-$$"
sandbox_make "$test_root"
server_pid=""
cleanup() { sandbox_remove "$test_root"; kill "$server_pid" 2>/dev/null; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-security.qml "$test_root/config/shell.qml" || exit 1

# A free loopback port, then the counter. Each GET appends its path, so the hits file both counts and names the vector that leaked.
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
hits="$test_root/hits.log"
: > "$hits" || exit 1
cat > "$test_root/serve.py" <<EOF
import http.server, zlib, struct, threading
CONTROL = threading.Event()
CONTROL_TIMEOUT_SECONDS = 25
HITS = "$hits"
def chunk(kind, body):
    c = struct.pack(">I", len(body)) + kind + body
    return c + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
PIXEL = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\x00\x00")) + chunk(b"IEND", b""))
class Count(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/drain":
            if not CONTROL.wait(CONTROL_TIMEOUT_SECONDS):
                self.send_error(504, "control image never fetched")
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"control landed")
            return
        with open(HITS, "a") as f:
            f.write(self.path + "\n")
        if self.path == "/control.png":
            CONTROL.set()
        body = PIXEL
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
http.server.ThreadingHTTPServer(("127.0.0.1", $port), Count).serve_forever()
EOF
python3 "$test_root/serve.py" & server_pid=$!
reached=""
for _ in $(seq 1 50); do
    if python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), timeout=1).close()" 2>/dev/null; then
        reached="yes"
        break
    fi
    sleep 0.1
done
if [ -z "$reached" ]; then
    printf 'FAIL the hit counter never answered on 127.0.0.1:%s\n' "$port"
    exit 1
fi

# The corpus. Every image URL points at the counter with a path naming its form and context (/f<form>/c<context>/x.png), so a hit names the leak. Bracketed [port] keeps one server for every spelling, including uppercase schemes.
python3 - "$test_root/notes.md" "$port" <<'EOF'
import sys
dest, port = sys.argv[1], sys.argv[2]
H = f"http://127.0.0.1:{port}"
forms = [
    ("altnosrc", lambda p: f'<img alt="![x]({H}/{p}/x.png)">'),
    ("altbadsrc", lambda p: f'<img src="x:y" alt="![x]({H}/{p}/x.png)">'),
    ("badge", lambda p: f'[![badge](pic.png)]({H}/{p}/x.png)'),
    ("gaptag", lambda p: f'!<bogus>[x]({H}/{p}/x.png)'),
    ("gapcomment", lambda p: f'!<!--gap-->[x]({H}/{p}/x.png)'),
    ("hostmarkup", lambda p: 'prefix <img src="http://a%3Cb%3Ex/x">'),
    ("hostentity", lambda p: 'prefix <img src="http://%3Cimg%20src=http%26%2347%3B%26%2347%3B127.0.0.1/x">'),
    ("inline", lambda p: f"![pic]({H}/{p}/x.png)"),
    ("titled", lambda p: f'![pic]({H}/{p}/x.png "a title")'),
    ("angle", lambda p: f"![pic](<{H}/{p}/x.png>)"),
    ("escaped", lambda p: f"![a\\]b]({H}/{p}/x.png)"),
    ("nested", lambda p: f"![a [b] c]({H}/{p}/x.png)"),
    ("fullref", lambda p: f"![pic][rid{p}]"),
    ("collapsed", lambda p: f"![cid{p}][]"),
    ("shortcut", lambda p: f"![sid{p}]"),
    ("multiline", lambda p: f"![pic][mid{p}]"),
    ("spacelabel", lambda p: f"![pic][my  id{p}]"),
    ("quotedef", lambda p: f"![pic][qid{p}]"),
    ("listdef", lambda p: f"![pic][lid{p}]"),
    ("entity", lambda p: f"![pic]({H}/{p}/a&#46;png)"),
    ("percent", lambda p: f"![pic]({H}/{p}/%78.png)"),
    ("protorel", lambda p: f"![pic](//127.0.0.1:{port}/{p}/x.png)"),
    ("upper", lambda p: f"![pic](HTTP://127.0.0.1:{port}/{p}/x.png)"),
    ("imgdq", lambda p: f'<img src="{H}/{p}/x.png" alt="pic">'),
    ("imgsq", lambda p: f"<img src='{H}/{p}/x.png' alt='pic'>"),
    ("imgbare", lambda p: f"<img src={H}/{p}/x.png alt=pic>"),
    ("tablebg", lambda p: f'<table background="{H}/{p}/x.png"><tr><td>hi</td></tr></table>'),
    ("stylebg", lambda p: f'<div style="background-image:url({H}/{p}/x.png)">hi</div>'),
    ("styleurl", lambda p: f'<p style="list-style:url({H}/{p}/x.png)">hi</p>'),
    ("base", lambda p: f'<base href="{H}/{p}/">'),
    ("link", lambda p: f'<link rel="stylesheet" href="{H}/{p}/x.css">'),
    ("inputimg", lambda p: f'<input type="image" src="{H}/{p}/x.png">'),
    ("videoposter", lambda p: f'<video poster="{H}/{p}/x.png"></video>'),
    ("svgimage", lambda p: f'<svg><image href="{H}/{p}/x.png"/></svg>'),
    ("bodybg", lambda p: f'<body background="{H}/{p}/x.png">hi</body>'),
    ("dataimg", lambda p: "![pic](data:image/png;base64,iVBORw0KGgo=)"),
]
defs = []
lines = ["# Security corpus", ""]
for fi, (name, make) in enumerate(forms):
    p = f"f{fi}"
    if name == "fullref":
        defs.append(f"[rid{p}]: {H}/{p}/x.png")
    elif name == "collapsed":
        defs.append(f"[cid{p}]: {H}/{p}/x.png")
    elif name == "shortcut":
        defs.append(f"[sid{p}]: {H}/{p}/x.png")
    elif name == "multiline":
        defs.append(f"[mid{p}]:\n  {H}/{p}/x.png")
    elif name == "spacelabel":
        defs.append(f"[My  Id{p}]: {H}/{p}/x.png")
    elif name == "quotedef":
        defs.append(f"> [qid{p}]: {H}/{p}/x.png")
    elif name == "listdef":
        defs.append(f"- [lid{p}]: {H}/{p}/x.png")
contexts = [
    ("alone", lambda s: [s, ""]),
    ("quote", lambda s: ["> " + s, ""]),
    ("quote2", lambda s: [">> " + s, ""]),
    ("list", lambda s: ["- " + s, ""]),
    ("list2", lambda s: ["  - " + s, ""]),
    ("list4", lambda s: ["    - " + s, ""]),
    ("ordered", lambda s: ["1. " + s, ""]),
    ("cell", lambda s: ["| " + s + " | x |", "| --- | --- |", ""]),
    ("htmlblock", lambda s: ["<div>", s, "</div>", ""]),
]
for fi, (name, make) in enumerate(forms):
    p = f"f{fi}"
    for ci, (cname, wrap) in enumerate(contexts):
        lines.append(f"<!-- {name} in {cname} -->")
        for wl in wrap(make(f"{p}c{ci}")):
            lines.append(wl)
        lines.append("")
lines.append("<!-- fenced controls stay literal -->")
lines.append("```")
lines.append(f"![fenced]({H}/fenced/x.png)")
lines.append("<img src=\"%s/fencedtag/x.png\">" % H)
lines.append("```")
lines.append("")
lines.append("Use `![span](%s/spancode/x.png)` for art." % H)
lines.append("")
lines.extend(defs)
lines.append("")
with open(dest, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"corpus forms={len(forms)} contexts={len(contexts)}")
EOF

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    FLEA_MARKDOWN_COUNTER="http://127.0.0.1:$port" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# The preview must have lived through its drain; without this line an empty qs output and a dead counter read as a pass.
if ! printf '%s\n' "$output" | grep -q 'MARKDOWN_SECURITY drained'; then
    printf 'FAIL the render harness never drained (no live preview ran)\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_SECURITY|ERROR|error' | head -20
    exit 1
fi
if ! grep -qx '/control.png' "$hits"; then
    echo 'FAIL positive control never reached the counter'
    exit 1
fi
count=$(grep -cvx '/control.png' "$hits" 2>/dev/null || true)
if [ "$count" -gt 0 ]; then
    printf 'FAIL %s remote request(s) left the preview\n' "$count"
    sort "$hits" | uniq -c | sort -rn | head -12
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_SECURITY' | head -5
    exit 1
fi
if printf '%s\n' "$output" | grep -q 'MARKDOWN_SECURITY FAIL'; then
    printf 'FAIL the preview refused its own fixture\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_SECURITY|ERROR' | head -10
    exit 1
fi
blocks=$(printf '%s\n' "$output" | grep -aoE 'blocks=[0-9]+' | head -1)
printf 'PASS zero remote requests (%s, corpus rendered)\n' "$blocks"
printf '%s\n' "$output" | grep -aE 'MARKDOWN_SECURITY' | head -5
