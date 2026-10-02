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

work=$(mktemp -d "${TMPDIR:-/tmp}/layer-drop.XXXXXXXX") || refuse "mktemp failed"
trap 'kill "$qs_pid" "$flea_pid" 2>/dev/null; rm -rf "$work"' EXIT
qs_pid=""; flea_pid=""
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
    if hyprctl layers -j 2>/dev/null | grep -q '"namespace": *"qs[^"]*"'; then qs_up=1; break; fi
    sleep 0.25
done
[ -n "$qs_up" ] || refuse "no Quickshell layer surface appeared"

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
omarchy-drive key --window flea t >/dev/null 2>&1 || true
sleep 1

# The tab strip sits under the chrome: drag the second tab below the window, onto empty
# desktop, and release. The drop point is read off the focused monitor, not assumed 1080p.
read -r mon_x mon_y mon_w mon_h < <(hyprctl monitors -j | python3 -c 'import json,sys; ms=json.load(sys.stdin); m=[x for x in ms if x.get("focused")] or ms; print(m[0]["x"],m[0]["y"],m[0]["width"],m[0]["height"])') || refuse "no focused monitor"
sx=$((mon_x + 300)); sy=$((mon_y + 105)); dx=$((mon_x + 300)); dy=$((mon_y + mon_h - 120))
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
move_to "$sx" "$sy"
sleep 0.4
ydotool click 0x40 >/dev/null 2>&1 || refuse "pointer press failed"
sleep 0.3
move_to "$dx" "$dy"
sleep 0.6
ydotool click 0x80 >/dev/null 2>&1 || refuse "pointer release failed"
sleep 1
if grep -q PANEL-DROP "$log"; then
    out "PASS"
    exit 0
fi
tail -5 "$work/qs.log" 2>/dev/null >&2 || true
refuse "no PANEL-DROP in $log"
