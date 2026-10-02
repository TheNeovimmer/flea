"""Exercise two real backend processes over one folder and one shared undo journal."""

import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time


class Backend:
    def __init__(self, binary, environment):
        self.process = subprocess.Popen(
            [binary, "--backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=environment,
        )
        self.answers = queue.Queue()
        self.errors = []
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        for line in self.process.stdout:
            try:
                self.answers.put(json.loads(line))
            except json.JSONDecodeError:
                self.answers.put({"t": "invalid", "line": line})

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def receive(self, kind):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            answer = self.answers.get(timeout=max(0.01, deadline - time.monotonic()))
            if answer.get("t") == "error":
                raise AssertionError(f"waiting for {kind}: {answer}")
            if answer.get("t") == kind:
                return answer
        raise AssertionError(f"no {kind} reply")

    def close(self):
        if self.process.poll() is None:
            self.send({"c": "quit"})
            self.process.stdin.close()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()


def main():
    binary, directory = sys.argv[1:]
    root = Path(directory)
    root.mkdir(parents=True, exist_ok=True)
    folder = root / "folder"
    folder.mkdir()
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), FLEA_UNDO_DIR=str(runtime / "flea"))
    backends = [Backend(binary, environment), Backend(binary, environment)]
    checks = 0

    def check(label, actual, expected):
        nonlocal checks
        checks += 1
        assert actual == expected, f"{label}: got {actual!r}, expected {expected!r}"
        print("ok   " + label)

    try:
        for backend in backends:
            backend.send({"c": "list", "path": str(folder), "first": 20})
            check("each backend lists the shared folder", backend.receive("listed")["n"], 0)
            backend.receive("rows")
        original = folder / "before.txt"
        original.write_text("shared bytes")
        for backend in backends:
            check("each watcher reports the outside create", backend.receive("changed")["path"], str(folder))
        backends[0].send({"c": "rename", "path": str(original), "to": "after.txt"})
        check("A's rename succeeds", backends[0].receive("renamed")["ok"], True)
        backends[1].send({"c": "undo"})
        check("B undoes A's rename", backends[1].receive("undone")["op"], "rename")
        check("B's undo restores the original bytes", original.read_text(), "shared bytes")
        check("B's undo removes the renamed path", (folder / "after.txt").exists(), False)
        backends[1].send({"c": "mkdir", "path": str(folder), "name": "made-by-b"})
        check("B's mkdir succeeds", backends[1].receive("made")["ok"], True)
        backends[0].send({"c": "undo"})
        check("A undoes B's mkdir", backends[0].receive("undone")["op"], "mkdir")
        check("A's undo removes B's directory", (folder / "made-by-b").exists(), False)
        print(f"xwsettings-backends: {checks} checks, 0 failed")
    finally:
        for backend in backends:
            backend.close()


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, queue.Empty) as error:
        print(f"FAIL xwsettings-backends: {error}")
        sys.exit(1)
