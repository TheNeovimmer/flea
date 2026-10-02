#!/bin/bash
# Probe: a drop on empty desktop reaches a Bottom-layer panel (xw6 item 3).
# The controller runs this natively on minipc under Hyprland; it prints one of
# PASS, FAIL or SKIP and exits 0, 1 or 2. Unattended: the drag is driven with
# ydotool through omarchy-drive, the same tools tests/ui.sh case_xwtab uses.
# A bare run needs FLEA_BIN on PATH or in the environment, qs, hyprctl,
# ydotool and omarchy-drive. With no compositor it prints SKIP.
set -u
need() { command -v "$1" >/dev/null 2>&1 || { printf 'SKIP missing %s\n' "$1"; exit 2; }; }
need qs; need hyprctl; need ydotool; need omarchy-drive
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || { printf 'SKIP no Hyprland session\n'; exit 2; }
flea_bin="${FLEA_BIN:-$(command -v flea || true)}"
[ -n "$flea_bin" ] || { printf 'SKIP no flea binary (set FLEA_BIN)\n'; exit 2; }
flea_ui="${FLEA_UI:-$(cd "$(dirname "$0")/../ui" && pwd)}"
[ -f "$flea_ui/boot/shell.qml" ] || { printf 'SKIP no Flea ui at %s (set FLEA_UI)\n' "$flea_ui"; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/layer-drop.XXXXXXXX") || exit 2
trap 'kill "$qs_pid" "$flea_pid" 2>/dev/null; rm -rf "$work"' EXIT
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
[ -n "$qs_up" ] || { printf 'FAIL no Quickshell layer surface appeared\n'; exit 1; }

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
[ -n "$addr" ] || { printf 'FAIL no Flea window came up\n'; exit 1; }
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

# The tab strip sits under the chrome: drag the second tab below the window,
# onto empty desktop, and release. Coordinates assume a 1080p monitor; the
# controller moves the window first if the box differs.
sx=300; sy=105; dx=300; dy=700
cur=$(hyprctl cursorpos | tr -d ',')
set -- $cur
cx=$1; cy=$2
ydotool mousemove -x $(( (sx - cx) / 2 )) -y $(( (sy - cy) / 2 )) >/dev/null 2>&1
sleep 0.3
set -- $(hyprctl cursorpos | tr -d ',')
ydotool mousemove -x $((sx - $1)) -y $((sy - $2)) >/dev/null 2>&1
sleep 0.4
ydotool click 0x40 >/dev/null 2>&1 || { printf 'FAIL pointer press failed\n'; exit 1; }
sleep 0.3
set -- $(hyprctl cursorpos | tr -d ',')
ydotool mousemove -x $(( (dx - $1) / 2 )) -y $(( (dy - $2) / 2 )) >/dev/null 2>&1
sleep 0.5
set -- $(hyprctl cursorpos | tr -d ',')
ydotool mousemove -x $((dx - $1)) -y $((dy - $2)) >/dev/null 2>&1
sleep 0.6
ydotool click 0x80 >/dev/null 2>&1 || { printf 'FAIL pointer release failed\n'; exit 1; }
sleep 1
if grep -q PANEL-DROP "$log"; then
    printf 'PASS a drop on empty desktop reached the Bottom-layer panel\n'
    exit 0
fi
printf 'FAIL no PANEL-DROP in %s; qs log tail:\n' "$log"
tail -5 "$work/qs.log" 2>/dev/null
exit 1
