#!/bin/bash
# Probe: a drop on empty desktop reaches a Bottom-layer panel (xw6 item 3).
# Controller runs this on minipc under Hyprland as `bash tests/probes/layer-drop-bottom.sh`
# with FLEA_BIN pointing at the built release binary (FLEA_UI defaults to this checkout's
# ui/); it also runs inside tests/ui.sh's environment, which provides the same two variables,
# omarchy-drive on PATH and the session's QT_QPA_PLATFORMTHEME. Either way it is unattended:
# bounded waits only, cleanup through the trap, and exactly one stdout line, either
# `LAYERDROP PASS` or `LAYERDROP FAIL <why>`; every diagnostic goes to stderr.
set -u
out() { printf 'LAYERDROP %s\n' "$*"; }
refuse() { out "FAIL $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || refuse "missing $1"; }
need qs; need hyprctl; need ydotool; need omarchy-drive
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || refuse "no Hyprland session"
flea_bin="${FLEA_BIN:-$(command -v flea || true)}"
[ -n "$flea_bin" ] || refuse "no flea binary (set FLEA_BIN)"
flea_ui="${FLEA_UI:-$(cd "$(dirname "$0")/../../ui" && pwd)}"
[ -f "$flea_ui/boot/shell.qml" ] || refuse "no Flea ui at $flea_ui (set FLEA_UI)"
probe_py="$(cd "$(dirname "$0")/.." && pwd)/xwtab_free_point.py"
[ -f "$probe_py" ] || refuse "no free-point helper at $probe_py"
verdict_sh="$(dirname "$0")/layer-drop-verdict.sh"
[ -f "$verdict_sh" ] || refuse "no verdict helper at $verdict_sh"
# shellcheck disable=SC1090
. "$verdict_sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/layer-drop.XXXXXXXX") || refuse "mktemp failed"
trap 'kill "$qs_pid" "$flea_pid" $torn 2>/dev/null; rm -rf "$work"' EXIT
qs_pid=""; flea_pid=""; torn=""
log="$work/panel.log"
: > "$log"

# A minimal Bottom-layer panel with a DropArea for the tab type. A drop appends
# PANEL-DROP through a shell escaping the QML string, so the check reads a file.
cat > "$work/panel.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.exclusiveZone: 0
            // The startup wait below matches this namespace exactly, never a qs prefix.
            WlrLayershell.namespace: "flea-layer-drop"
            DropArea {
                anchors.fill: parent
                keys: ["application/x-flea-tab"]
                onDropped: function (drop) {
                    Quickshell.execDetached(["sh", "-c", "printf 'PANEL-DROP\\\\n' >> '$log'"])
                }
            }
        }
    }
}
EOF

setsid qs -p "$work/panel.qml" >"$work/qs.log" 2>&1 &
qs_pid=$!
qs_up=""
for _ in $(seq 1 40); do
    if hyprctl layers -j 2>/dev/null | grep -Fq '"namespace": "flea-layer-drop"'; then qs_up=1; break; fi
    sleep 0.25
done
if [ -z "$qs_up" ]; then tail -5 "$work/qs.log" 2>/dev/null >&2 || true; refuse "no Quickshell layer surface appeared"; fi

# A Flea window with two tabs is the drag source: the strip is hidden for one.
srcdir="$work/src"
mkdir -p "$srcdir/sub"
FLEA_UI="$flea_ui" FLEA_BIN="$flea_bin" setsid nohup "$flea_bin" --gui "$srcdir" >"$work/flea.log" 2>&1 </dev/null &
flea_pid=$!
addr=""
for _ in $(seq 1 60); do
    addr=$(hyprctl clients -j | python3 -c '
import json, sys
hits = [c for c in json.load(sys.stdin) if str(c.get("pid")) == sys.argv[1]]
print(hits[0]["address"] if len(hits) == 1 else "")
' "$flea_pid") || true
    [ -n "$addr" ] && break
    sleep 0.5
done
[ -n "$addr" ] || refuse "no Flea window came up"
hyprctl dispatch "hl.dsp.focus({ window = \"$addr\" })" >/dev/null
sleep 0.4
hyprctl dispatch "hl.dsp.window.float()" >/dev/null
sleep 0.3
hyprctl dispatch "hl.dsp.window.move({ x = 40, y = 40 })" >/dev/null
sleep 0.3
hyprctl dispatch "hl.dsp.window.resize({ x = 900, y = 500 })" >/dev/null
sleep 0.5
# The qs instance id for this pid, same lookup tests/ui.sh uses for its tabs.
qid=""
for _ in $(seq 1 60); do
    qid=$(qs list --all --json 2>/dev/null | python3 -c '
import json, sys
hits = [x for x in json.load(sys.stdin) if x.get("config_path") == sys.argv[1] and x.get("pid") == int(sys.argv[2])]
print(hits[0]["id"] if len(hits) == 1 else "")
' "$flea_ui/boot/shell.qml" "$flea_pid") || true
    [ -n "$qid" ] && break
    sleep 0.5
done
[ -n "$qid" ] || refuse "no qs instance for $flea_pid"
omarchy-drive key --window flea t >/dev/null 2>&1 || true
# The strip only lifts with two tabs, so wait for the second one like the case does.
two=""
for _ in $(seq 1 40); do
    if [ "$(qs ipc -i "$qid" call flea tabCount 2>/dev/null || true)" = "2" ]; then two=1; break; fi
    sleep 0.25
done
[ -n "$two" ] || refuse "t did not open a second tab"
sleep 0.5
# The lifted folder, read through the same qs ipc reader the case uses for its tabs.
lifted_path=$(qs ipc -i "$qid" call flea path 2>/dev/null || true)
[ -n "$lifted_path" ] || refuse "no path for the lifted tab"
# The drag starts on the second tab centre, never on a guessed chrome offset.
centre=$(qs ipc -i "$qid" call flea tabCentre 1 2>/dev/null || true)
[ -n "$centre" ] || refuse "second tab has no centre"
read -r cx cy <<< "$centre"
read -r wx wy _ww _wh < <(hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
hits = [c for c in json.load(sys.stdin) if str(c.get("pid")) == sys.argv[1]]
print("%s %s %s %s" % (hits[0]["at"][0], hits[0]["at"][1], hits[0]["size"][0], hits[0]["size"][1]) if hits else "")
' "$flea_pid" || true)
[ -n "${wx:-}" ] || refuse "no geometry for $flea_pid"
sx=$((wx + cx)); sy=$((wy + cy))
# The release uses the same free-point scan the case uses, after the park above.
mon_json=$(hyprctl monitors -j 2>/dev/null || true)
[ -n "$mon_json" ] || refuse "no monitors to scan"
read -r mx my mw mh mon_name < <(printf '%s' "$mon_json" | python3 -c '
import json, sys
ms = json.load(sys.stdin)
m = [x for x in ms if x.get("focused")] or ms
print(m[0]["x"], m[0]["y"], m[0]["width"], m[0]["height"], m[0].get("name", ""))
' || true)
[ -n "${mon_name:-}" ] || refuse "no focused monitor to scan"
hyprctl clients -j 2>/dev/null > "$work/clients.json" || refuse "no clients to scan"
# The own panel receives the drop, so it is filtered out of the cover like the case filters nothing yet mapped.
hyprctl layers -j 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
for entry in (d.values() if isinstance(d, dict) else []):
    lv = entry.get("levels") if isinstance(entry, dict) else None
    if not isinstance(lv, dict):
        continue
    for k in list(lv.keys()):
        v = lv[k]
        if isinstance(v, list):
            lv[k] = [n for n in v if not (isinstance(n, dict) and n.get("namespace") == "flea-layer-drop")]
print(json.dumps(d))
' > "$work/layers.json" || refuse "no layers to scan"
printf '%s' "$mon_json" > "$work/monitors.json"
point=$(python3 "$probe_py" "$mx" "$my" "$mw" "$mh" "$mon_name" "$work/clients.json" "$work/layers.json" "$work/monitors.json" || true)
[ -n "$point" ] || refuse "no empty desktop point on the focused monitor"
read -r dx dy <<< "$point"
# The Bottom panel must still be mapped at release, or the drop has no receiver.
hyprctl layers -j 2>/dev/null | grep -Fq '"namespace": "flea-layer-drop"' || refuse "Bottom panel went away before the drop"
move_to() {
    local tx="$1" ty="$2" i cx cy
    for i in $(seq 1 16); do
        set -- $(hyprctl cursorpos | tr -d ',')
        cx=$1; cy=$2
        if [ "$((tx - cx))" -le 4 ] && [ "$((tx - cx))" -ge -4 ] && [ "$((ty - cy))" -le 4 ] && [ "$((ty - cy))" -ge -4 ]; then return 0; fi
        ydotool mousemove -x "$(((tx - cx) / 2))" -y "$(((ty - cy) / 2))" >/dev/null 2>&1 || refuse "pointer motion failed"
        sleep 0.05
    done
    refuse "pointer did not reach $tx,$ty"
}
# Flea windows before the drop: its own Bottom catcher may take the drop and tear off instead.
before_flea=$(pgrep -x qs | while read -r pid; do tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" | grep -Fq "$flea_ui" && printf '%s ' "$pid"; done)
move_to "$sx" "$sy"
sleep 0.4
ydotool click 0x40 >/dev/null 2>&1 || refuse "pointer press failed"
sleep 0.3
move_to "$dx" "$dy"
sleep 0.6
ydotool click 0x80 >/dev/null 2>&1 || refuse "pointer release failed"
sleep 1
# The qs instance id for a torn-off pid, same lookup the case uses for its tabs.
layerdrop_qsid() {
    local pid="$1" i tid
    for i in $(seq 1 20); do
        tid=$(qs list --all --json 2>/dev/null | python3 -c '
import json, sys
hits = [x for x in json.load(sys.stdin) if x.get("config_path") == sys.argv[1] and x.get("pid") == int(sys.argv[2])]
print(hits[0]["id"] if len(hits) == 1 else "")
' "$flea_ui/boot/shell.qml" "$pid") || true
        if [ -n "$tid" ]; then printf '%s' "$tid"; return 0; fi
        sleep 0.5
    done
    return 1
}
if layerdrop_panel_hit "$log"; then
    out "PASS"
    exit 0
fi
# The drop reached Flea's own Bottom catcher instead: a new owned window reads
# as the lifted folder through the same qs ipc reader the case uses for its tabs.
after_flea=$(pgrep -x qs | while read -r pid; do tr '\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" | grep -Fq "$flea_ui" && printf '%s ' "$pid"; done)
torn=$(layerdrop_torn_pids "$before_flea" "$after_flea")
paths_tsv=""
for pid in $torn; do
    tid=$(layerdrop_qsid "$pid" || true)
    [ -n "${tid:-}" ] || continue
    seen=""
    for _ in $(seq 1 30); do
        seen=$(qs ipc -i "$tid" call flea path 2>/dev/null || true)
        layerdrop_path_matches "$seen" "$lifted_path" && break
        sleep 0.5
    done
    paths_tsv="${paths_tsv}${pid}$(printf '\t')${seen}
"
    if layerdrop_path_matches "$seen" "$lifted_path"; then
        printf 'torn-off window %s took the drop on %s\n' "$pid" "$seen" >&2
        out "PASS"
        exit 0
    fi
done
printf 'flea windows before: %s after: %s\n' "$before_flea" "$after_flea" >&2
printf 'lifted folder: %s torn: %s paths: %s\n' "$lifted_path" "$torn" "$(printf '%s' "$paths_tsv" | tr '\n' ';')" >&2
tail -5 "$work/qs.log" 2>/dev/null >&2 || true
refuse "no PANEL-DROP in $log and no torn-off window"
