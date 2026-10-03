#!/usr/bin/env python3
"""Fault injection into picker phase classification and selection output capture."""
from pathlib import Path
import os
import subprocess
import tempfile

REPO = Path(__file__).resolve().parent.parent
TIMEOUT_SECONDS = "0.05"
PRODUCER_SLEEP_SECONDS = 1
NOISY_LOG_BYTES = 1024 * 1024
SELECTION_WRAPPER_TIMEOUT_SECONDS = 10
STUB_EXECUTABLE_MODE = 0o755
QML_SUCCESS_EXIT = 0
QML_ASSERTION_EXIT = 1
QML_TIMEOUT_EXIT = 124
checks = 0
failures = 0

for name in ["picker-hunt", "picker-040"]:
    source = (REPO / "tests" / (name + ".sh")).read_text()
    # Sample input: code=$? follows captured qs output; warnings precede the phase-loop closing lines.
    begin = source.index("        code=$?")
    end = source.index("    done", begin)
    classify = source[begin:end]
    with tempfile.TemporaryDirectory(prefix="picker-runner-check-") as scratch:
        phase = Path(scratch)
        (phase / "reply.json").write_text('{"response":0,"uris":["file://' + scratch + '/a.txt"]}')
        for fault in ["timeout", "crash", "sigpipe", "clean-noisy"]:
            producer = "print('PICKER_HUNT DONE 1 checks, 0 failed', flush=True)"
            if fault == "timeout":
                command = ["timeout", TIMEOUT_SECONDS, "python3", "-c", "import time; " + producer + "; time.sleep(" + str(PRODUCER_SLEEP_SECONDS) + ")"]
            elif fault == "crash":
                command = ["python3", "-c", producer + "; raise SystemExit(139)"]
            else:
                prefix = "PICKER_HUNT FAIL injected\n" if fault == "sigpipe" else "PICKER_HUNT DONE 1 checks, 0 failed\n"
                command = ["python3", "-c", "import sys; sys.stdout.write(" + repr(prefix) + " + 'x' * " + str(NOISY_LOG_BYTES) + ")"]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            (phase / "output").write_text(result.stdout)
            script = '''set -uo pipefail
phase=$1
fixture=$phase
preset=default
view=list
scenario=$2
failures=0
phases=0
output=$(cat "$phase/output")
(exit "$3")
''' + classify + '''printf '%s: %s phases, %s failed\n' "$4" "$phases" "$failures"
[ "$failures" -eq 0 ]
'''
            verdict = subprocess.run(["bash", "-c", script, "check", scratch,
                                      "cursor-open" if name == "picker-hunt" else "path", str(result.returncode), name],
                                     capture_output=True, text=True, check=False)
            rejected = verdict.returncode != 0
            wanted = fault != "clean-noisy"
            status_line = fault not in ["timeout", "crash"] or ("FAIL " in verdict.stdout and "exit=" + str(result.returncode) in verdict.stdout)
            checks += 1
            ok = rejected == wanted and status_line
            failures += not ok
            print(("PASS " if ok else "FAIL ") + name + " " + fault + " producer=" + str(result.returncode)
                  + " classifier=" + str(verdict.returncode))
            if not ok:
                for line in verdict.stdout.splitlines():
                    if not line.startswith("x"):
                        print(line[:300])
with tempfile.TemporaryDirectory(prefix="picker-selection-runner-check-") as scratch:
    commands = Path(scratch) / "bin"
    commands.mkdir()
    for name in ["python3", "cargo"]:
        command = commands / name
        command.write_text("#!/bin/sh\nexit 0\n")
        command.chmod(STUB_EXECUTABLE_MODE)
    qml = commands / "qml6"
    qml.write_text('''#!/bin/sh
printf '%s\\n' 'selection runner sentinel' >&2
printf '%s\\n' 'picker-selection QML: 1 checks, 0 failed'
exit "$PICKER_QML_STATUS"
''')
    qml.chmod(STUB_EXECUTABLE_MODE)
    for status in [QML_SUCCESS_EXIT, QML_ASSERTION_EXIT, QML_TIMEOUT_EXIT]:
        environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                           TMPDIR=scratch, PICKER_QML_STATUS=str(status))
        result = subprocess.run(["bash", str(REPO / "tests/picker-selection.sh")], env=environment,
                                capture_output=True, text=True, check=False, timeout=SELECTION_WRAPPER_TIMEOUT_SECONDS)
        checks += 1
        ok = result.returncode == status and "selection runner sentinel" in result.stdout
        failures += not ok
        print(("PASS " if ok else "FAIL ") + "picker-selection preserves output and exit=" + str(status)
              + " observed=" + str(result.returncode) + " printed=" + str(bool(result.stdout)))
print(f"picker-runner-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
