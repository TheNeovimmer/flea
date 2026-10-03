#!/usr/bin/env python3
"""Refuse the named operation once, then accept the same file without filesystem changes."""
import json
import os
from pathlib import Path
import sys
import time

# Let native key events move focus or cancel while the check is outstanding.
SUBMISSION_DELAY_SECONDS = 0.15

if "--ui-state" in sys.argv:
    print("{}", flush=True)
    sys.exit(0)

scenario = os.environ["FLEA_PICKER_HUNT_CASE"]
refusal_log = Path(os.environ["FLEA_PICKER_HUNT_REFUSAL_LOG"])
# Sample FLEA_PICKER: {"mode": "open", "multiple": false, "folder": "/tmp/picker", "name": "a.txt", "title": "Picker hunt", "filters": [{"label": "Text", "globs": ["*.txt"], "mimes": []}]}
folder = json.loads(os.environ["FLEA_PICKER"])["folder"]
path = str(Path(folder) / "a.txt")
mark = {"path": path, "uri": Path(path).as_uri(), "bytes": 1}
rows = [{"n": "a.txt", "d": False, "s": 1, "m": 1, "p": 33188, "i": "text-x-generic", "t": False, "k": 0}]
refused_operation = {"refuse-mark": "mark", "refuse-validate": "validate", "refuse-review": "review"}.get(scenario, "mark")
attempts = {operation: 0 for operation in ("mark", "validate", "review")}


def emit(value):
    print(json.dumps(value), flush=True)


for line in sys.stdin:
    # Sample stdin line: {"op":"validate","c":"picker","id":1}
    request = json.loads(line)
    command = request["c"]
    if command == "list":
        emit({"t": "listed", "n": 1, "read": 0, "sort": 0, "path": folder})
        emit({"t": "rows", "start": 0, "rows": rows, "ms": 0, "kinds": []})
    elif command == "fsinfo":
        emit({"t": "fsinfo", "fs": "tmpfs", "free": 1, "path": folder, "class": "internal"})
    elif command == "window":
        emit({"t": "rows", "start": 0, "rows": rows, "ms": 0, "kinds": []})
    elif command == "picker":
        operation = request["op"]
        reply = {"t": "picker", "id": request.get("id", 0), "op": operation, "ok": True}
        if operation == "save":
            reply.update(path=path, review=1, collision=scenario == "refuse-collision")
        elif operation in ("mark", "validate", "review"):
            attempts[operation] += 1
            time.sleep(SUBMISSION_DELAY_SECONDS)
            if operation == refused_operation and attempts[operation] == 1:
                with refusal_log.open("a") as log:
                    log.write(operation + "\n")
                print("PICKER_HUNT REFUSED " + operation, file=sys.stderr, flush=True)
                reply.update(ok=False, error=f"Could not inspect {path}: permission denied")
            else:
                reply.update(path=path, marks=[mark])
        emit(reply)
    elif command == "quit":
        break
