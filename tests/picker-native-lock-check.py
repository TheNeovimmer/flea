#!/usr/bin/env python3
"""Exercise the native runner's lock path without loading GI or starting a display."""
import ast
import contextlib
import io
import fcntl
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = ast.parse(Path(__file__).with_name("picker-native.py").read_text())
namespace = dict(os=os, fcntl=fcntl, Path=Path, re=re, subprocess=subprocess, processes=[])
# Sample input: def start(...): child = subprocess.Popen(..., close_fds=True).
launchers = [node for node in source.body if isinstance(node, ast.FunctionDef) and node.name in {"run", "start", "guard"}]
exec(compile(ast.Module(body=launchers, type_ignores=[]), "picker-native.py", "exec"), namespace)
helper = next((node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == "take_display_lock"), None)
if helper:
    exec(compile(ast.Module(body=[helper], type_ignores=[]), "picker-native.py", "exec"), namespace)
    take_lock = namespace["take_display_lock"]
else:
    # Sample input: display_lock = open(...); fcntl.flock(display_lock, LOCK_EX | LOCK_NB).
    body = next(node.body for node in source.body if isinstance(node, ast.Try))
    start = next(index for index, node in enumerate(body) if isinstance(node, ast.Assign)
                 and any(isinstance(target, ast.Name) and target.id == "display_lock" for target in node.targets))
    old = compile(ast.Module(body=body[start:start + 2], type_ignores=[]), "picker-native.py", "exec")
    def take_lock(runtime):
        namespace["drive_env"] = {"XDG_RUNTIME_DIR": runtime}
        exec(old, namespace)
        return namespace["display_lock"]

checks = 0
failures = 0
CHILD_TIMEOUT_SECONDS = 5
FD_PROBE = '''import errno
import os
import sys
try:
    os.fstat(int(sys.argv[1]))
except OSError as error:
    if error.errno != errno.EBADF:
        raise
    print("closed")
else:
    print("inherited")
'''

def check(label, action):
    global checks, failures
    checks += 1
    try:
        action()
        print("PASS " + label)
    except Exception as error:
        failures += 1
        print("FAIL " + label + ": " + str(error))

with tempfile.TemporaryDirectory(prefix="picker-native-lock-") as runtime:
    namespace["root"] = Path(runtime)
    (Path(runtime) / ".flea-test-sandbox").write_text("")
    os.environ.pop("FLEA_DISPLAY_LOCK_FD", None)
    def unset():
        with take_lock(runtime):
            with open(Path(runtime) / "flea-display.lock", "a") as contender:
                try:
                    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    return
                raise AssertionError("unset path did not acquire lock")
    check("unset opens and locks runtime file", unset)
    with open(Path(runtime) / "flea-display.lock", "a") as owned:
        fcntl.flock(owned, fcntl.LOCK_EX | fcntl.LOCK_NB)
        os.environ["FLEA_DISPLAY_LOCK_FD"] = str(owned.fileno())
        os.set_inheritable(owned.fileno(), True)
        def inherited():
            with take_lock(runtime) as held:
                assert held.fileno() != owned.fileno(), "runner must retain its own duplicate"
            os.fstat(owned.fileno())
        check("inherited lock stays owned", inherited)
        arguments = [sys.executable, "-c", FD_PROBE, str(owned.fileno())]
        def run_child():
            result = namespace["run"](arguments)
            assert result == "closed", "run() child inherited display lock fd"
        check("production run() closes inherited lock fd", run_child)
        def start_child():
            child = namespace["start"](arguments, "lock-child", dict(os.environ))
            try:
                status = child.wait(timeout=CHILD_TIMEOUT_SECONDS)
                result = (Path(runtime) / "lock-child.log").read_text().strip()
                assert status == 0, "start() probe failed: " + result
                assert result == "closed", "start() child inherited display lock fd"
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=CHILD_TIMEOUT_SECONDS)
        check("production start() closes inherited lock fd", start_child)
        for value in ["", "9x", "-1", "999999", "9" * 100]:
            os.environ["FLEA_DISPLAY_LOCK_FD"] = value
            def invalid():
                try:
                    with contextlib.redirect_stdout(io.StringIO()) as output:
                        held = take_lock(runtime)
                except (AssertionError, ValueError, OSError, OverflowError) as error:
                    assert "FAIL" in str(error) and output.getvalue().startswith("FAIL "), "invalid fd did not fail loud"
                    return
                held.close()
                raise AssertionError("invalid fd accepted")
            check("invalid inherited fd " + repr(value), invalid)
os.environ.pop("FLEA_DISPLAY_LOCK_FD", None)
print(f"picker-native-lock-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
