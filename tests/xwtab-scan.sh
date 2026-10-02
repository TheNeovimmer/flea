#!/bin/bash
# Headless check for the xwtab free-desktop scan, same code the case runs.
# Fabricated monitors, clients and layers prove level 0 is skipped, other
# workspaces are skipped, levels 1 to 3 on the focused monitor still block.
set -u
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
pass=0
fail=0
ok() { printf 'ok %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*" >&2; fail=$((fail+1)); }
scratch=$(mktemp -d) || exit 1
case $scratch in /*/*) ;; *) echo "FAIL mktemp gave $scratch" >&2; exit 1 ;; esac
trap 'rm -rf "$scratch"' EXIT
# One focused monitor, DP-2 at 0 0 2560 1440, active workspace 1, no special.
cat > "$scratch/monitors.json" <<'EOF'
[{"name":"DP-2","x":0,"y":0,"width":2560,"height":1440,"focused":true,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":0,"name":""}}]
EOF
# Levels carry a fullscreen level 0 background, a fullscreen qs catcher on 1
# and the real bar strip on 2, the exact minipc shape the tear-off hit.
cat > "$scratch/layers.json" <<'EOF'
{"DP-2":{"levels":{"0":[{"address":"0x1","x":0,"y":0,"w":2560,"h":1440,"namespace":"omarchy-background","pid":100}],"1":[{"address":"0x2","x":0,"y":0,"w":2560,"h":1440,"namespace":"qs-tearoff","pid":200}],"2":[{"address":"0x3","x":0,"y":0,"w":2560,"h":30,"namespace":"omarchy-bar","pid":300}],"3":[]}}}
EOF
# Active bottom cover plus a fullscreen client on workspace 2, plus one hidden
# and one unmapped row that never cover anything on any workspace.
cat > "$scratch/clients.json" <<'EOF'
[{"address":"0xa","mapped":true,"hidden":false,"at":[0,1000],"size":[2560,440],"workspace":{"id":1,"name":"1"},"floating":true,"monitor":1,"class":"x","title":"t","pid":1000},{"address":"0xb","mapped":true,"hidden":false,"at":[0,0],"size":[2560,1440],"workspace":{"id":2,"name":"2"},"floating":false,"monitor":1,"class":"x","title":"t","pid":1001},{"address":"0xc","mapped":true,"hidden":true,"at":[0,0],"size":[2560,1440],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":1,"class":"x","title":"t","pid":1002},{"address":"0xd","mapped":false,"hidden":false,"at":[0,0],"size":[2560,1440],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":1,"class":"x","title":"t","pid":1003}]
EOF
got=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients.json" "$scratch/layers.json" "$scratch/monitors.json" || true)
# Bottom cover ends at y 1000, so the bottom-up 24 px grid first frees at 976.
if [ "$got" = "8 976" ]; then
ok "level 0 plus other workspace skipped, active bottom kept: $got"
else
bad "level 0 plus other workspace skipped, want '8 976', got '$got'"
fi
# Old scan at fb5d999e counted every layer and every client, so the same three
# files leave it no point at all and the caller fails on the empty answer.
old=$(python3 -c '
import json,sys
mx,my,mw,mh=[int(v) for v in sys.argv[1:5]]
clients=json.load(open(sys.argv[5]))
layers=json.load(open(sys.argv[6]))
rects=[[c["at"][0],c["at"][1],c["size"][0],c["size"][1]] for c in clients]
def harvest(node):
    global rects
    if isinstance(node,dict):
        if all(k in node for k in ("x","y","w","h")) and "namespace" in node:
            ns=str(node["namespace"])
            full=node["x"]==mx and node["y"]==my and node["w"]==mw and node["h"]==mh
            if not (ns.startswith("qs") and full):
                rects.append([node["x"],node["y"],node["w"],node["h"]])
        for v in node.values():
            harvest(v)
    elif isinstance(node,list):
        for v in node:
            harvest(v)
harvest(layers)
def covered(px,py):
    return any(rx<=px<rx+rw and ry<=py<ry+rh for rx,ry,rw,rh in rects)
for py in range(my+mh-8,my-1,-24):
    for px in range(mx+8,mx+mw-8,24):
        if not covered(px,py):
            print(px,py)
            raise SystemExit(0)
print("")
' 0 0 2560 1440 "$scratch/clients.json" "$scratch/layers.json" || true)
if [ -z "$old" ]; then
ok "old scan at fb5d999e finds no point on the same files"
else
bad "old scan at fb5d999e should find no point, got '$old'"
fi
# Without the level 0 background the other-workspace fullscreen alone still
# blocks the old scan, while the new one keeps the same 8 976 answer.
cat > "$scratch/layers-nobg.json" <<'EOF'
{"DP-2":{"levels":{"0":[],"1":[],"2":[{"address":"0x3","x":0,"y":0,"w":2560,"h":30,"namespace":"omarchy-bar","pid":300}],"3":[]}}}
EOF
got2=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients.json" "$scratch/layers-nobg.json" "$scratch/monitors.json" || true)
if [ "$got2" = "8 976" ]; then
ok "other workspace alone is skipped: $got2"
else
bad "other workspace alone is skipped, want '8 976', got '$got2'"
fi
old2=$(python3 -c '
import json,sys
mx,my,mw,mh=[int(v) for v in sys.argv[1:5]]
clients=json.load(open(sys.argv[5]))
layers=json.load(open(sys.argv[6]))
rects=[[c["at"][0],c["at"][1],c["size"][0],c["size"][1]] for c in clients]
def harvest(node):
    global rects
    if isinstance(node,dict):
        if all(k in node for k in ("x","y","w","h")) and "namespace" in node:
            ns=str(node["namespace"])
            full=node["x"]==mx and node["y"]==my and node["w"]==mw and node["h"]==mh
            if not (ns.startswith("qs") and full):
                rects.append([node["x"],node["y"],node["w"],node["h"]])
        for v in node.values():
            harvest(v)
    elif isinstance(node,list):
        for v in node:
            harvest(v)
harvest(layers)
def covered(px,py):
    return any(rx<=px<rx+rw and ry<=py<ry+rh for rx,ry,rw,rh in rects)
for py in range(my+mh-8,my-1,-24):
    for px in range(mx+8,mx+mw-8,24):
        if not covered(px,py):
            print(px,py)
            raise SystemExit(0)
print("")
' 0 0 2560 1440 "$scratch/clients.json" "$scratch/layers-nobg.json" || true)
if [ -z "$old2" ]; then
ok "old scan blocked by the other workspace alone"
else
bad "old scan should be blocked by the other workspace alone, got '$old2'"
fi
# A layer on another monitor never covers this one, even fullscreen on level 2.
cat > "$scratch/layers-foreign.json" <<'EOF'
{"DP-2":{"levels":{"0":[],"1":[],"2":[{"address":"0x3","x":0,"y":0,"w":2560,"h":30,"namespace":"omarchy-bar","pid":300}],"3":[]}},"DP-1":{"levels":{"0":[],"1":[],"2":[{"address":"0x9","x":0,"y":0,"w":2560,"h":1440,"namespace":"other-bar","pid":900}],"3":[]}}}
EOF
cat > "$scratch/clients-empty.json" <<'EOF'
[]
EOF
got3=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients-empty.json" "$scratch/layers-foreign.json" "$scratch/monitors.json" || true)
if [ "$got3" = "8 1432" ]; then
ok "foreign monitor layer is skipped: $got3"
else
bad "foreign monitor layer is skipped, want '8 1432', got '$got3'"
fi
# Levels 1 to 3 on the focused monitor still block, so a bottom cover that
# leaves only the bar strip reports empty instead of a point inside the bar.
cat > "$scratch/clients-fullbelow.json" <<'EOF'
[{"address":"0xe","mapped":true,"hidden":false,"at":[0,30],"size":[2560,1410],"workspace":{"id":1,"name":"1"},"floating":false,"monitor":1,"class":"x","title":"t","pid":1004}]
EOF
got4=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients-empty.json" "$scratch/layers.json" "$scratch/monitors.json" || true)
# No client, only bar plus ignored background and qs, so bottom stays free.
if [ "$got4" = "8 1432" ]; then
ok "bar alone leaves the bottom free: $got4"
else
bad "bar alone leaves the bottom free, want '8 1432', got '$got4'"
fi
got5=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients-fullbelow.json" "$scratch/layers-nobg.json" "$scratch/monitors.json" || true)
if [ -z "$got5" ]; then
ok "bar plus a full-below cover reports empty"
else
bad "bar plus a full-below cover should report empty, got '$got5'"
fi
# An open special workspace covers like the active one, a closed one is ignored.
cat > "$scratch/monitors-special.json" <<'EOF'
[{"name":"DP-2","x":0,"y":0,"width":2560,"height":1440,"focused":true,"activeWorkspace":{"id":1,"name":"1"},"specialWorkspace":{"id":99,"name":"special"}}]
EOF
cat > "$scratch/clients-special.json" <<'EOF'
[{"address":"0xf","mapped":true,"hidden":false,"at":[0,1000],"size":[2560,440],"workspace":{"id":99,"name":"special"},"floating":false,"monitor":1,"class":"x","title":"t","pid":1005}]
EOF
got6=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients-special.json" "$scratch/layers-nobg.json" "$scratch/monitors-special.json" || true)
if [ "$got6" = "8 976" ]; then
ok "open special workspace covers: $got6"
else
bad "open special workspace covers, want '8 976', got '$got6'"
fi
got7=$(python3 "$repo/tests/xwtab_free_point.py" 0 0 2560 1440 DP-2 "$scratch/clients-special.json" "$scratch/layers-nobg.json" "$scratch/monitors.json" || true)
if [ "$got7" = "8 1432" ]; then
ok "closed special workspace is skipped: $got7"
else
bad "closed special workspace is skipped, want '8 1432', got '$got7'"
fi
# The tear-off count compares normalised sets, so a leading space, a doubled
# space and a duplicate collapse to the same sorted unique set.
. "$repo/tests/xwtab-norm.sh" || { bad "cannot source xwtab-norm.sh"; }
norm=$(xwtab_norm_set " 160643 159605 160229 159605 " || true)
if [ "$norm" = "159605 160229 160643" ]; then
ok "leading space plus duplicate normalises: $norm"
else
bad "leading space plus duplicate normalises, want '159605 160229 160643', got '$norm'"
fi
norm_empty=$(xwtab_norm_set "" || true)
if [ -z "$norm_empty" ]; then
ok "empty set stays empty"
else
bad "empty set stays empty, got '$norm_empty'"
fi
# The probe verdict against the native lines that failed it: before "169083 "
# and after "169083 169306 " is one torn pid, and a torn window reading as the
# lifted folder through the qs ipc reader is the drop reaching the catcher.
. "$repo/tests/probes/layer-drop-verdict.sh" || { bad "cannot source layer-drop-verdict.sh"; }
torn_case=$(layerdrop_torn_pids "169083 " "169083 169306 " || true)
if [ "$torn_case" = "169306" ]; then
ok "native before/after leaves one torn pid: $torn_case"
else
bad "native before/after leaves one torn pid, want '169306', got '$torn_case'"
fi
paths_case=$(printf '169306\t%s' "/fake/layer-drop/src")
if layerdrop_any_on_path "$torn_case" "/fake/layer-drop/src" "$paths_case"; then
ok "a torn window on the lifted folder is the drop reaching the catcher"
else
bad "a torn window on the lifted folder should count as the drop reaching the catcher"
fi
if layerdrop_any_on_path "$torn_case" "/fake/layer-drop/src" "$(printf '169306\t%s' "/elsewhere")"; then
bad "a torn window on another folder must not count as the drop reaching the catcher"
else
ok "a torn window on another folder does not count"
fi
if layerdrop_any_on_path "" "/fake/layer-drop/src" "$paths_case"; then
bad "no torn window must not count as the drop reaching the catcher"
else
ok "no torn window does not count"
fi
printf 'PANEL-DROP\n' > "$scratch/panel-hit.log"
if layerdrop_panel_hit "$scratch/panel-hit.log"; then
ok "the probe panel route still passes on its own log line"
else
bad "the probe panel route should still pass on its own log line"
fi
: > "$scratch/panel-miss.log"
if layerdrop_panel_hit "$scratch/panel-miss.log"; then
bad "an empty panel log must not count as the panel taking the drop"
else
ok "an empty panel log does not count"
fi
# The probe shares this verdict file, so a revert of its verdict section reddens here too.
if grep -q 'FLEA_PATH=$srcdir' "$repo/tests/probes/layer-drop-bottom.sh"; then
bad "the probe verdict still keys on the torn window environ"
else
ok "the probe verdict no longer keys on the torn window environ"
fi
if grep -q 'layerdrop_torn_pids' "$repo/tests/probes/layer-drop-bottom.sh"; then
ok "the probe verdict shares the torn computation above"
else
bad "the probe verdict should share the torn computation above"
fi
# Hyprland selectors built from an address need the address: prefix.
# A bare address resolves nothing while the dispatcher still returns ok.
bare=$(grep -rnE 'window[[:space:]]*=[[:space:]]*\\?"(\$|0x|\{)' "$repo/tests" --exclude=xwtab-scan.sh || true)
if [ -n "$bare" ]; then
bad "bare window selector without address: prefix: $bare"
else
ok "every window selector carries the address: prefix"
fi
# Exercise the live trace helpers with launch logs, including stale events before both marks.
flea_log="$scratch/flea.log"
run_root="$scratch"
printf 'qml: TABDRAG drag-finished pid=101 old=true\n' > "$flea_log"
printf 'qml: TABDRAG enter-window pid=202 old=true\n' > "$run_root/flea-second.log"
eval "$(sed -n '/^xwtab_logs=/,/^# The addr and rect/p' "$repo/tests/ui.sh")"
xwtab_source=101; xwtab_target=202; xwtab_gesture="test press"
xwtab_mark_logs
printf 'qml: TABDRAG drag-start pid=101 index=1\n' >> "$flea_log"
printf 'qml: TABDRAG enter-window pid=202 ok=true\n' >> "$run_root/flea-second.log"
expected=$(printf 'qml: TABDRAG drag-start pid=101 index=1\nqml: TABDRAG enter-window pid=202 ok=true')
if [ "$(xwtab_trace_lines)" = "$expected" ]; then
ok "both live launch logs are read after their own pre-press marks"
else
bad "trace reader mixed in stale events or missed a launch log"
fi
if (fail() { exit 1; }; xwtab_wait_start; xwtab_wait_enter 202 require); then
ok "source start and target enter accept the marked launch traces"
else
bad "marked source start and target enter should satisfy the waits"
fi
if (hyprctl() { printf '281, 106\n'; }; xwtab_rect_of() { printf '0xa 165 65 1000 720 True\n'; }; readlink() { printf 'test launch log\n'; }; xwtab_dump_trace) > "$scratch/dump.out" 2> "$scratch/dump.err" \
    && [ ! -s "$scratch/dump.out" ] && grep -Fq 'TABDRAG drag-start pid=101' "$scratch/dump.err" \
    && grep -Fq 'TABDRAG enter-window pid=202' "$scratch/dump.err" && ! grep -Fq old=true "$scratch/dump.err"; then
ok "failure dump prints both marked traces to stderr without hiding them"
else
bad "failure dump hid output, printed stale trace or wrote to stdout"
fi
printf 'qml: TABDRAG drag-finished pid=101 action=0\n' >> "$flea_log"
if (fail() { exit 1; }; xwtab_wait_enter 202 require); then
bad "a source finishing before release must fail even with a target enter"
else
ok "a source finishing before release is refused"
fi
# Run the real gesture helper against a compositor and pointer recorder.
: > "$scratch/own-strip.out"
(
    fail() { exit 1; }
    xwdrag_glide() { printf 'glide %s %s\n' "$1" "$2"; }
    xwdrag_geometry() { printf '165 65 1000 720\n'; }
    xwtab_mark_logs() { printf 'mark\n'; }
    xwtab_wait_start() { printf 'start\n'; }
    xwtab_wait_enter() { printf 'enter %s %s\n' "$1" "$2"; }
    ydotool() { printf 'pointer %s %s\n' "$1" "$2" >> "$scratch/own-strip.out"; }
    xwtab_drag_to_window 501 106 281 106 101 101 require
) >> "$scratch/own-strip.out"
expected=$(printf 'glide 501 106\nmark\npointer click 0x40\nglide 365 845\nstart\nglide 281 106\nglide 287 106\nglide 281 106\nstart\nenter 101 require\npointer click 0x80')
if [ "$(cat "$scratch/own-strip.out")" = "$expected" ]; then
ok "own-strip drag crosses the actual window edge before waiting for its own enter"
else
bad "own-strip drag did not leave its source before returning and releasing"
fi
# A reused pid is not enough: the layer probe must read back its exact client address.
(
    addr=0xa; flea_pid=101
    hyprctl() { printf '%s\n' '[{"address":"0xb","pid":101,"at":[900,600],"size":[500,300],"floating":false},{"address":"0xa","pid":101,"at":[40,40],"size":[900,500],"floating":true}]'; }
    eval "$(sed -n '/^layerdrop_rect()/,/^layerdrop_focus()/p' "$repo/tests/probes/layer-drop-bottom.sh" | sed '$d')"
    layerdrop_rect
) > "$scratch/probe-rect.out"
if [ "$(cat "$scratch/probe-rect.out")" = "40 40 900 500 True" ]; then
ok "layer probe geometry belongs to its address and pid after the move"
else
bad "layer probe geometry selected another client"
fi
printf '%s checks, %s failed\n' "$((pass+fail))" "$fail"
exit "$((fail>0))"
