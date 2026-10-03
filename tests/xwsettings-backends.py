"""Exercise two real backend processes over one folder and one shared undo journal."""

from collections import deque
import io
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import threading
import time
from unittest.mock import patch

REPLY_TIMEOUT_SECONDS = 8
MIN_QUEUE_WAIT_SECONDS = 0.01
STDERR_BUFFER_CHUNKS = 32
STDERR_CHUNK_CHARS = 4096
CHATTER_LINES = 512
SHUTDOWN_TIMEOUT_SECONDS = 5


class Backend:
    def __init__(self, binary, environment):
        self.process = subprocess.Popen(
            [binary, "--backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, env=environment,
        )
        self.answers = queue.Queue()
        self.errors = deque(maxlen=STDERR_BUFFER_CHUNKS)
        self.error_lock = threading.Lock()
        threading.Thread(target=self.read, daemon=True).start()
        self.stderr_reader = threading.Thread(target=self.read_errors, daemon=True)
        self.stderr_reader.start()

    def read(self):
        for line in self.process.stdout:
            try:
                # Sample reply: {"t":"listed","n":0} is one JSON line on stdout.
                self.answers.put(json.loads(line))
            except json.JSONDecodeError:
                self.answers.put({"t": "invalid", "line": line})

    def read_errors(self):
        while chunk := self.process.stderr.readline(STDERR_CHUNK_CHARS):
            with self.error_lock:
                self.errors.append(chunk)

    def report_errors(self):
        with self.error_lock:
            retained = "".join(self.errors)
        if retained:
            print(f"backend {self.process.pid} stderr:", file=sys.stderr)
            print(retained, file=sys.stderr, end="")

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def receive(self, kind):
        deadline = time.monotonic() + REPLY_TIMEOUT_SECONDS
        while time.monotonic() < deadline:
            try:
                answer = self.answers.get(timeout=max(MIN_QUEUE_WAIT_SECONDS, deadline - time.monotonic()))
            except queue.Empty as error:
                raise AssertionError(f"no {kind} reply") from error
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
                self.process.wait(timeout=SHUTDOWN_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.stderr_reader.join(timeout=SHUTDOWN_TIMEOUT_SECONDS)


def check_timeouts(check):
    quiet = Backend.__new__(Backend)
    quiet.answers = queue.Queue()
    for kind in ("listed", "rows"):
        with patch.object(quiet.answers, "get", side_effect=queue.Empty):
            try:
                quiet.receive(kind)
            except (AssertionError, queue.Empty) as error:
                detail = str(error)
            else:
                detail = "returned without a reply"
        check(f"timeout names awaited {kind} reply", detail, f"no {kind} reply")


def check_stderr(check, environment):
    child = """
import json
import sys
for index in range(int(sys.argv[1])):
    sys.stderr.write("chatty diagnostic " + "x" * int(sys.argv[2]) + "\\n")
sys.stderr.write("last stderr diagnostic\\n")
sys.stderr.flush()
print(json.dumps({"t": "stderr-ready"}), flush=True)
for line in sys.stdin:
    # Sample request: {"c":"quit"} terminates the synthetic backend.
    if json.loads(line).get("c") == "quit":
        break
"""
    popen = subprocess.Popen
    with patch("subprocess.Popen", side_effect=lambda command, **kwargs: popen(
        [sys.executable, "-c", child, str(CHATTER_LINES), str(STDERR_CHUNK_CHARS)], **kwargs,
    )):
        backend = Backend("chatty-backend", environment)
    try:
        check("stderr flood cannot block a backend reply", backend.receive("stderr-ready")["t"], "stderr-ready")
    finally:
        backend.close()
    retained = "".join(backend.errors)
    check("stderr diagnostics stay bounded", len(retained) <= STDERR_BUFFER_CHUNKS * STDERR_CHUNK_CHARS, True)
    check("stderr diagnostics retain the final line", retained.endswith("last stderr diagnostic\n"), True)
    output = io.StringIO()
    with patch("sys.stderr", output):
        backend.report_errors()
    check("failure report prints retained stderr", "last stderr diagnostic\n" in output.getvalue(), True)


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

    failed = True
    try:
        check_timeouts(check)
        check_stderr(check, environment)
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
        failed = False
    finally:
        for backend in backends:
            backend.close()
            if failed:
                backend.report_errors()


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, queue.Empty) as error:
        print(f"FAIL xwsettings-backends: {error}")
        sys.exit(1)
