#!/usr/bin/env python3
"""The app and compositor that tests/ui-process-ownership.py runs case_xwsettings against.

qs, omarchy-drive, hyprctl, flea, pgrep and world are one-line launchers that pass their own name as the first
argument. Every call is appended to calls.jsonl, and the windows, the compositor focus and the keys they receive
live in state.json beside it.
The settings both windows share live in the XDG_STATE_HOME ui.json, the way the product keeps them.
"""
import fcntl
import json
import os
import shutil
import sys
import time
from pathlib import Path

FIRST_ROWS_BASE_MS = 1759400000000
FIRST_ROWS_STEP_MS = 1000
PID_BASE = 5000
ADDRESS_BASE = 0x1000
WINDOW_CLASS = "com.thisisgm.flea"
SECTIONS = ("view", "keys")
CONTROLS = ("density", "rows")
ROW_HEIGHTS = {"compact": 28, "normal": 32}
# The poll gap of a wait that has to see a window another call registers, and its bound when the call names none.
WAIT_POLL_S = 0.02
WAIT_DEFAULT_S = 15

home = Path(os.environ["FLEA_WORLD"])
run_root = Path(os.environ["FLEA_TEST_RUN_ROOT"])
tool = sys.argv[1]
args = sys.argv[2:]
home.mkdir(parents=True, exist_ok=True)
lock = open(home / "lock", "a")
fcntl.flock(lock, fcntl.LOCK_EX)
with open(home / "calls.jsonl", "a") as log:
    log.write(json.dumps({"tool": tool, "argv": args, "timeout": os.environ.get("WORLD_TIMEOUT", "")}) + "\n")
state_file = home / "state.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {"seq": 0, "windows": [], "active": None}


def ui_file():
    return Path(os.environ["XDG_STATE_HOME"]) / "flea" / "ui.json"


def ui_read():
    return json.loads(ui_file().read_text()) if ui_file().exists() else {}


def ui_write(patch):
    ui_file().parent.mkdir(parents=True, exist_ok=True)
    ui_file().write_text(json.dumps({**ui_read(), **patch}))


def window_with(key, value):
    return next((w for w in state["windows"] if w[key] == value), None)


def newest():
    return state["windows"][-1] if state["windows"] else None


def rows(w):
    names = os.listdir(w["path"])
    if not ui_read().get("hidden"):
        names = [n for n in names if not n.startswith(".")]
    return sorted(names, key=lambda n: (not os.path.isdir(os.path.join(w["path"], n)), n))


def row_at(w, index):
    names = rows(w)
    return names[index] if index < len(names) else None


def ipc(w, fn, fargs):
    s = w["settings"]
    active = state["active"] == w["address"]
    answers = {
        "path": lambda: w["path"],
        "cursor": lambda: w["cursor"],
        "total": lambda: len(rows(w)),
        "rowAt": lambda: (row_at(w, int(fargs[0])) or "") + "|",
        "visibleRowName": lambda: row_at(w, int(fargs[0])) or "",
        "listInFlight": lambda: "false",
        "state": lambda: "ready",
        "viewMode": lambda: w["view"],
        "showHidden": lambda: str(bool(ui_read().get("hidden"))).lower(),
        "fileRowHeight": lambda: ROW_HEIGHTS[ui_read().get("density", "compact")],
        "focusView": lambda: "list",
        "firstRowsAt": lambda: os.environ.get("WORLD_STAMP", w["first_rows"]),
        "keyDeliveryState": lambda: json.dumps({"activeFocusItem": f"Row_QMLTYPE_1({w['pid']:#x})" if active else "null"}),
        "settingsSections": lambda: json.dumps([{"id": i} for i in SECTIONS] if s else []),
        "settingsSide": lambda: s["side"] if s else "",
        "settingsSection": lambda: SECTIONS[s["section"]] if s else "",
        "settingsModel": lambda: json.dumps([{"id": i} for i in CONTROLS] if s else []),
        "settingsCursor": lambda: s["cursor"] if s else -1,
        "uiSettings": lambda: json.dumps({"density": "compact", **ui_read()}),
    }
    return answers[fn]()


def clamp(value, size):
    return max(0, min(size - 1, value))


def press(w, key, ctrl):
    s = w["settings"]
    if s:
        if key == "Escape":
            w["settings"] = None
        elif key == "Tab":
            s["side"] = "pane" if s["side"] == "rail" else "rail"
        elif key in ("j", "k") and s["side"] == "rail":
            s["section"] = clamp(s["section"] + (1 if key == "j" else -1), len(SECTIONS))
        elif key in ("j", "k"):
            s["cursor"] = clamp(s["cursor"] + (1 if key == "j" else -1), len(CONTROLS))
        elif key == "l" and s["side"] == "pane" and CONTROLS[s["cursor"]] == "density":
            ui_write({"density": "normal"})
    elif ctrl and key == "3":
        w["view"] = "grid"
    elif key in ("j", "k"):
        w["cursor"] = clamp(w["cursor"] + (1 if key == "j" else -1), len(rows(w)))
    elif key == ".":
        ui_write({"hidden": not ui_read().get("hidden")})
    elif key == ",":
        w["settings"] = {"side": "rail", "section": 0, "cursor": 0}
    elif key == "Return" and os.path.isdir(os.path.join(w["path"], row_at(w, w["cursor"]))):
        w["path"], w["cursor"] = os.path.join(w["path"], row_at(w, w["cursor"])), 0


def clients():
    pids = [w["pid"] for w in state["windows"]]
    # A compositor that reports each window under the other's client pid.
    if os.environ.get("WORLD_SWAP_PIDS"):
        pids.reverse()
    return [{"address": w["address"], "class": WINDOW_CLASS, "title": "Flea", "pid": pid, "at": [12, 42], "size": [880, 620]}
            for w, pid in zip(state["windows"], pids)]


def register(ui, path):
    # A launch whose window never appears, so the run leaves no pids file.
    if os.environ.get("WORLD_NO_WINDOW"):
        return
    state["seq"] += 1
    seq = state["seq"]
    pid = PID_BASE + seq
    address = hex(ADDRESS_BASE + seq)
    state["windows"].append({"address": address, "pid": pid, "path": path, "cursor": 0, "view": "list", "settings": None,
                             "first_rows": FIRST_ROWS_BASE_MS + FIRST_ROWS_STEP_MS * seq})
    state["active"] = address
    proc = run_root / "proc" / str(pid)
    proc.mkdir(parents=True)
    (proc / "cmdline").write_bytes(f"qs\0-p\0{ui}/boot\0".encode())
    tag = "/foreign" if os.environ.get("WORLD_FOREIGN") else str(run_root)
    (proc / "environ").write_bytes(f"FLEA_TEST_RUN_ROOT={tag}\0".encode())
    with open(home / "pids", "a") as pids:
        pids.write(f"{pid}\n")


def reply(w, spec):
    if w is None:
        sys.exit(1)
    print(ipc(w, spec[0], spec[1:]))


def keys_of(rest):
    # Sample: -M ctrl -k 3 -m ctrl is Ctrl+3, and a bare j is the key j.
    key, ctrl, i = None, False, 0
    while i < len(rest):
        if rest[i] in ("-M", "-m", "-k"):
            ctrl = ctrl or (rest[i] == "-M" and rest[i + 1] == "ctrl")
            key = rest[i + 1] if rest[i] == "-k" else key
            i += 2
        else:
            key, i = rest[i], i + 1
    return key, ctrl


if tool == "hyprctl" and args[0] == "activewindow":
    active = window_with("address", state["active"])
    print(json.dumps({"class": WINDOW_CLASS, "address": active["address"]} if active else {}))
elif tool == "hyprctl" and args[0] == "clients":
    print(json.dumps(clients()))
elif tool == "pgrep":
    if args[-1] != "qs" or not state["windows"]:
        sys.exit(1)
    print("\n".join(str(w["pid"]) for w in state["windows"]))
elif tool == "flea" and args[0] == "--ui-state":
    ui_write(json.loads(args[1]))
elif tool == "flea" and args[0] == "--gui":
    register(os.environ["FLEA_UI"], args[1])
elif tool == "world" and args[0] == "kill":
    victim = window_with("pid", int(args[1]))
    if victim:
        state["windows"].remove(victim)
        gone = run_root / "proc" / args[1]
        # Hard rule 9: only a fake process directory inside this run's marked root is ever deleted.
        assert run_root.is_absolute() and (run_root / ".flea-test-sandbox").is_file() and gone.parent.parent == run_root
        shutil.rmtree(gone)
        state["active"] = newest()["address"] if newest() else None
elif tool == "qs":
    # Sample: ipc --pid 5001 call flea cursor; a qs that ignored --pid would answer from the newest instance.
    pid_route = os.environ.get("WORLD_ROUTE") != "newest"
    reply(window_with("pid", int(args[2])) if pid_route else newest(), args[5:])
elif tool == "omarchy-drive" and args[0] == "ipc":
    # Sample: ipc -p /ui/boot flea cursor; every tree declares ShellId flea, so the newest instance answers a path.
    reply(newest(), args[4:])
elif tool == "omarchy-drive" and args[0] == "wait":
    # The real wait blocks until the window exists; the lock is let go so the launch that makes it can register.
    # Sample: wait window flea --timeout 15
    if os.environ.get("WORLD_NO_WINDOW"):
        sys.exit(1)
    bound = float(args[args.index("--timeout") + 1]) if "--timeout" in args else WAIT_DEFAULT_S
    deadline = time.monotonic() + bound
    fcntl.flock(lock, fcntl.LOCK_UN)
    while time.monotonic() < deadline:
        if state_file.exists() and json.loads(state_file.read_text()).get("windows"):
            sys.exit(0)
        time.sleep(WAIT_POLL_S)
    sys.exit(1)
elif tool == "omarchy-drive" and args[0] == "windows":
    fields = ("address", "class", "title", "at", "size")
    print(json.dumps({"ok": True, "windows": [{k: c[k] for k in fields} for c in clients()]}))
elif tool == "omarchy-drive" and args[0] == "focus":
    state["active"] = args[1]
elif tool == "omarchy-drive" and args[0] == "key":
    # Sample: key --window 0x1001 -k Return; a key reaches only the window the compositor has active.
    key, ctrl = keys_of(args[3:])
    if state["active"] == args[2]:
        press(window_with("address", args[2]), key, ctrl)
else:
    sys.exit(2)
(home / "state.tmp").write_text(json.dumps(state))
os.replace(home / "state.tmp", state_file)
