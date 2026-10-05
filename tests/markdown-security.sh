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
cp tests/mdfence.js "$test_root/config/mdfence.js" || exit 1
cp tests/mdhtmlsecurity.js "$test_root/config/mdhtmlsecurity.js" || exit 1

# A free loopback port, then the counter. Each GET appends its path, so the hits file both counts and names the vector that leaked.
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
hits="$test_root/hits.log"
: > "$hits" || exit 1
cat > "$test_root/serve.py" <<EOF
import http.server, zlib, struct, threading
CONTROL = threading.Event()
CONTROL_TIMEOUT_SECONDS = 25
DELAY_SECONDS = 2
DELAY_COMPLETE = threading.Event()
HITS = "$hits"
def chunk(kind, body):
    c = struct.pack(">I", len(body)) + kind + body
    return c + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
PIXEL = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00\x00\x00")) + chunk(b"IEND", b""))
class Count(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/reset":
            CONTROL.clear()
            self.send_response(200)
            self.end_headers()
            return
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
        if self.path == "/delayed-corpus.png":
            threading.Timer(DELAY_SECONDS, DELAY_COMPLETE.set).start()
            DELAY_COMPLETE.wait(CONTROL_TIMEOUT_SECONDS)
        if self.path == "/control.png":
            if not DELAY_COMPLETE.is_set():
                with open(HITS, "a") as f:
                    f.write("/control-before-delayed-ready\n")
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
    ("badge-inner", lambda p: f'[![b]({H}/{p}/badge.png)](local.md)'),
    ("badge-html", lambda p: f'[<img src="{H}/{p}/badge.png">](local.md)'),
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
    ("table-quote-name", lambda p: f'<table \' title="\' background={H}/{p}/x.png \'" \' ><tr><td>hi</td></tr></table>'),
    ("stylebg", lambda p: f'<div style="background-image:url({H}/{p}/x.png)">hi</div>'),
    ("styleurl", lambda p: f'<p style="list-style:url({H}/{p}/x.png)">hi</p>'),
    ("base", lambda p: f'<base href="{H}/{p}/">'),
    ("link", lambda p: f'<link rel="stylesheet" href="{H}/{p}/x.css">'),
    ("inputimg", lambda p: f'<input type="image" src="{H}/{p}/x.png">'),
    ("videoposter", lambda p: f'<video poster="{H}/{p}/x.png"></video>'),
    ("svgimage", lambda p: f'<svg><image href="{H}/{p}/x.png"/></svg>'),
    ("script-unquoted-slash", lambda p: f'<script a=b/>![x]({H}/{p}/x.png)</script>'),
    ("style-unquoted-slash", lambda p: f'<style a=b/>![x]({H}/{p}/x.png)</style>'),
    ("svg-unquoted-slash", lambda p: f'<svg a=b/>![x]({H}/{p}/x.png)</svg>'),
    ("bodybg", lambda p: f'<body background="{H}/{p}/x.png">hi</body>'),
    ("dataimg", lambda p: "![pic](data:image/png;base64,iVBORw0KGgo=)"),
    ("onclick-attr", lambda p: f'<p onclick="alert(1)" onmouseover="alert(2)">R13CLICKTEXT {p}</p>'),
    ("onerror-attr", lambda p: '<img src="x.png" onerror="alert(1)" alt="R13ERRORTEXT">'),
    ("js-link-html", lambda p: '<a href="javascript:alert(1)">R13JSTEXT</a>'),
    ("js-link-md", lambda p: '[R13JSTEXT](javascript:alert(1))'),
]
DROP_CONTENT_NAMES = ("script", "style", "iframe", "object", "embed", "template", "noscript", "svg", "math")
NON_HTML_WHITESPACE = ("\u00a0", "\u000b", "\u2003", "\ufeff")
HTML_WHITESPACE = ("\t", "\n", "\f", "\r", " ")
tag_forms = [("initial-equals", " ==/", False), ("equals-name", " =a/", False)]
for index, char in enumerate(NON_HTML_WHITESPACE):
    tag_forms.extend([(f"value-non-html-{index}", f" a=b{char}/", False),
        (f"head-non-html-{index}", f"{char}a=b/", False)])
for index, char in enumerate(HTML_WHITESPACE):
    tag_forms.extend([(f"value-html-{index}", f" a=b{char}/", True),
        (f"head-html-{index}", f"{char}a=b /", True)])
for tag_name in DROP_CONTENT_NAMES:
    for label, tail, self_close in tag_forms:
        sentinel = "R9_KEEP_BODY" if self_close else "R9_DROP_BODY"
        forms.append((f"drop-{tag_name}-{label}", lambda p, tag_name=tag_name, tail=tail, sentinel=sentinel:
            f"<{tag_name}{tail}>{sentinel} ![x]({H}/{p}/x.png)</{tag_name}> R9_TAIL"))
defs = []
# Front matter and display math lines reach the screen as code, so an image written there must stay literal text.
lines = ["---", f"title: ![front]({H}/frontmatter/x.png)", f"[front]({H}/frontmatter/link.png)", "---", "", "# Security corpus", ""]
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
reference_prefixes = {"fullref": "rid", "collapsed": "cid", "shortcut": "sid", "multiline": "mid",
    "spacelabel": "My  Id", "quotedef": "qid", "listdef": "lid"}
for fi, (name, make) in enumerate(forms):
    p = f"f{fi}"
    for ci, (cname, wrap) in enumerate(contexts):
        context_path = f"{p}c{ci}"
        if name in reference_prefixes:
            label = reference_prefixes[name] + context_path
            separator = "\n  " if name == "multiline" else " "
            prefix = "> " if name == "quotedef" else "- " if name == "listdef" else ""
            defs.append(f"{prefix}[{label}]:{separator}{H}/{context_path}/x.png")
        lines.append(f"<!-- {name} in {cname} -->")
        for wl in wrap(make(context_path)):
            lines.append(wl)
        lines.append("")
lines.append("<!-- fenced controls stay literal -->")
lines.append("```")
lines.append(f"![fenced]({H}/fenced/x.png)")
lines.append("<img src=\"%s/fencedtag/x.png\">" % H)
lines.append("```")
lines.append("")
# A fence inside an item or a quote stays verbatim for the renderer, so an image or a tag written there must not load.
for fence_name, fence_prefix in (("fencedlist", "- "), ("fencedquote", "> "), ("fencedordered", "1. "), ("fencednested", "- a\n  - ")):
    pad = " " * len(fence_prefix.rsplit("\n", 1)[-1]) if fence_prefix.startswith("-") or fence_prefix[0].isdigit() else fence_prefix
    first = fence_prefix + "```"
    inner = [f"![x]({H}/{fence_name}/x.png)", f'<img src="{H}/{fence_name}/tag.png">', "```"]
    lines.append("<!-- %s -->" % fence_name)
    lines.extend([first] + [(pad if fence_prefix[0] != ">" else "> ") + row for row in inner])
    lines.append("")
lines.append("Use `![span](%s/spancode/x.png)` for art." % H)
lines.append("")
lines.append("<!-- display math lines stay literal -->")
lines.extend(["$$", f"![math]({H}/mathblock/x.png)", f'<img src="{H}/mathblock/tag.png">', "$$", ""])
lines.extend([f"$$![math]({H}/mathline/x.png)$$", ""])
lines.extend(["$$ open", f"![math]({H}/mathopen/x.png)", "$$ close", ""])
lines.extend(defs)
lines.append("")
with open(dest, "w") as f:
    f.write("\n".join(lines) + "\n")
print(f"corpus forms={len(forms)} contexts={len(contexts)}")
EOF

# A Source view failure is reported under its own name, before any drain or fixture verdict can claim it.
source_view_verdict() {
    local line
    line=$(printf '%s\n' "$1" | grep -a -m1 'MARKDOWN_SECURITY FAIL Source view') || return 0
    printf 'FAIL %s\n' "${line#*MARKDOWN_SECURITY FAIL }"
    exit 1
}

# The delayed negative control must finish before the control and still fail the zero-hit check.
delayed_output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    FLEA_MARKDOWN_COUNTER="http://127.0.0.1:$port" FLEA_MARKDOWN_DELAYED_CORPUS=1 \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

source_view_verdict "$delayed_output"
if ! printf '%s\n' "$delayed_output" | grep -q 'MARKDOWN_SECURITY reference forms resolved'; then
    echo 'FAIL reference forms did not resolve before the delayed network check'
    printf '%s\n' "$delayed_output"
    exit 1
fi
if ! grep -qx '/delayed-corpus.png' "$hits" || grep -qx '/control-before-delayed-ready' "$hits" \
    || ! printf '%s\n' "$delayed_output" | grep -q 'MARKDOWN_SECURITY drained' \
    || printf '%s\n' "$delayed_output" | grep -q 'MARKDOWN_SECURITY FAIL'; then
    echo 'FAIL delayed corpus Image did not drain before control'
    printf '%s\n' "$delayed_output"
    cat "$hits"
    exit 1
fi
delayed_count=$(grep -cvx '/control.png' "$hits" 2>/dev/null || true)
echo "ok delayed corpus counted ($delayed_count remote request(s)), completed before control"
: > "$hits"
python3 - "$port" <<'RESET'
import sys, urllib.request
urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/reset").read()
RESET

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    FLEA_MARKDOWN_COUNTER="http://127.0.0.1:$port" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

source_view_verdict "$output"
# The preview must have lived through its drain; without this line an empty qs output and a dead counter read as a pass.
if ! printf '%s\n' "$output" | grep -q 'MARKDOWN_SECURITY drained'; then
    printf 'FAIL the render harness never drained (no live preview ran)\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_SECURITY|ERROR|error' | head -20
    exit 1
fi
if ! printf '%s\n' "$output" | grep -q 'MARKDOWN_SECURITY reference forms resolved'; then
    echo 'FAIL reference forms did not resolve before the network check'
    printf '%s\n' "$output"
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
