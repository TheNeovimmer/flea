#!/usr/bin/env python3
# Free desktop point for the xwtab tear-off, shared by tests/ui.sh and tests/xwtab-scan.sh.
# Counts only what can take the drop: mapped non-hidden clients on the focused
# monitor active workspace (or its open special workspace), plus layers on
# levels 1 to 3 of the focused monitor, minus the fullscreen qs catcher.
# Level 0 is the wallpaper under the Bottom catcher and never takes the drop.
# Clients on other workspaces never cover the desktop either.
import json
import sys
def monitor_entry(monitors, mon_name):
    # Pick the focused monitor by name, else the focused flag, else the first.
    if isinstance(monitors, list) and monitors:
        for m in monitors:
            if isinstance(m, dict) and m.get("name") == mon_name:
                return m
        for m in monitors:
            if isinstance(m, dict) and m.get("focused"):
                return m
        if isinstance(monitors[0], dict):
            return monitors[0]
    return {}
def workspace_ids(entry):
    # Active id plus the special id only when one is open (nonzero).
    active = None
    special = None
    aw = entry.get("activeWorkspace", None)
    if isinstance(aw, dict):
        active = aw.get("id", None)
    elif isinstance(aw, int):
        active = aw
    sw = entry.get("specialWorkspace", None)
    if isinstance(sw, dict):
        special = sw.get("id", None)
    elif isinstance(sw, int):
        special = sw
    valid = set()
    try:
        if active is not None and int(active) != 0:
            valid.add(int(active))
    except (TypeError, ValueError):
        pass
    try:
        if special is not None and int(special) != 0:
            valid.add(int(special))
    except (TypeError, ValueError):
        pass
    return valid
def client_rects(clients, valid):
    # Only mapped, non-hidden clients on a valid workspace cover the desktop.
    # Empty valid means the active workspace is unknown, so keep every mapped row.
    rects = []
    if not isinstance(clients, list):
        return rects
    for c in clients:
        if not isinstance(c, dict):
            continue
        if not c.get("mapped"):
            continue
        if c.get("hidden"):
            continue
        if valid:
            ws = c.get("workspace", None)
            wid = ws.get("id", None) if isinstance(ws, dict) else ws
            try:
                wid = int(wid)
            except (TypeError, ValueError):
                continue
            if wid not in valid:
                continue
        try:
            at = c.get("at", None)
            sz = c.get("size", None)
            x = int(at[0])
            y = int(at[1])
            w = int(sz[0])
            h = int(sz[1])
        except (TypeError, ValueError, IndexError):
            continue
        rects.append([x, y, w, h])
    return rects
def layer_rects(layers, mon_name, mx, my, mw, mh):
    # Only levels 1, 2 and 3 of the focused monitor, read off the levels key.
    rects = []
    if not isinstance(layers, dict):
        return rects
    entry = layers.get(mon_name, None)
    if not isinstance(entry, dict):
        return rects
    levels = entry.get("levels", None)
    if not isinstance(levels, dict):
        return rects
    for key in ("1", "2", "3"):
        items = None
        if key in levels:
            items = levels[key]
        elif int(key) in levels:
            items = levels[int(key)]
        else:
            continue
        if not isinstance(items, list):
            continue
        for node in items:
            if not isinstance(node, dict):
                continue
            if not all(k in node for k in ("x", "y", "w", "h")):
                continue
            ns = str(node.get("namespace", ""))
            try:
                x = int(node["x"])
                y = int(node["y"])
                w = int(node["w"])
                h = int(node["h"])
            except (TypeError, ValueError):
                continue
            full = x == mx and y == my and w == mw and h == mh
            if ns.startswith("qs") and full:
                continue
            rects.append([x, y, w, h])
    return rects
def find_free_point(mx, my, mw, mh, rects):
    # Bottom-up 24 px grid, first uncovered point wins, empty when none is free.
    def covered(px, py):
        for rx, ry, rw, rh in rects:
            if rx <= px < rx + rw and ry <= py < ry + rh:
                return True
        return False
    for py in range(my + mh - 8, my - 1, -24):
        for px in range(mx + 8, mx + mw - 8, 24):
            if not covered(px, py):
                return (px, py)
    return None
def main(argv):
    # Args: MX MY MW MH MON_NAME CLIENTS_JSON LAYERS_JSON MONITORS_JSON.
    if len(argv) != 9:
        sys.stderr.write("usage: xwtab_free_point.py MX MY MW MH MON_NAME CLIENTS LAYERS MONITORS\n")
        return 2
    try:
        mx = int(argv[1])
        my = int(argv[2])
        mw = int(argv[3])
        mh = int(argv[4])
    except ValueError:
        sys.stderr.write("xwtab_free_point: monitor geometry is not numeric\n")
        return 2
    mon_name = argv[5]
    try:
        with open(argv[6], "r", encoding="utf-8") as f:
            clients = json.load(f)
        with open(argv[7], "r", encoding="utf-8") as f:
            layers = json.load(f)
        with open(argv[8], "r", encoding="utf-8") as f:
            monitors = json.load(f)
    except (OSError, ValueError) as e:
        sys.stderr.write("xwtab_free_point: could not read input: %s\n" % e)
        return 2
    entry = monitor_entry(monitors, mon_name)
    valid = workspace_ids(entry)
    rects = client_rects(clients, valid)
    rects.extend(layer_rects(layers, mon_name, mx, my, mw, mh))
    found = find_free_point(mx, my, mw, mh, rects)
    if found is None:
        sys.stdout.write("\n")
    else:
        sys.stdout.write("%d %d\n" % found)
    return 0
if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
