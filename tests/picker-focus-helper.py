#!/usr/bin/env python3
"""Refuse the first submission, then accept the same file without filesystem changes."""
import json
import os
from pathlib import Path
import sys
import time

if "--ui-state" in sys.argv:
    print("{}", flush=True)
    sys.exit(0)

scenario = os.environ["FLEA_PICKER_HUNT_CASE"]
folder = json.loads(os.environ["FLEA_PICKER"])["folder"]
path = str(Path(folder) / "a.txt")
mark = {"path": path, "uri": Path(path).as_uri(), "bytes": 1}
rows = [{"n": "a.txt", "d": False, "s": 1, "m": 1, "p": 33188, "i": "text-x-generic", "t": False, "k": 0}]
attempts = 0


def emit(value):
    print(json.dumps(value), flush=True)


for line in sys.stdin:
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
            attempts += 1
            # Let native key events move focus or cancel while the check is outstanding.
            time.sleep(0.15)
            if attempts == 1:
                reply.update(ok=False, error=f"Could not inspect {path}: permission denied")
            else:
                reply.update(path=path, marks=[mark])
        emit(reply)
    elif command == "quit":
        break
