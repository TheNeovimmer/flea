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
ROW_PROBE_TIMEOUT_SECONDS = 5
ROW_PROBE_GRACE_SECONDS = 1
HELD_ROW_OFFSET = 60
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

with tempfile.TemporaryDirectory(prefix="picker-missing-helper-") as scratch:
    probe = Path(scratch)
    (probe / "picker-native-lock-check.py").write_text((REPO / "tests/picker-native-lock-check.py").read_text())
    # Sample input: def take_display_lock(runtime_dir): defines the required native lock helper.
    native = (REPO / "tests/picker-native.py").read_text().replace("def take_display_lock(", "def missing_display_lock(")
    (probe / "picker-native.py").write_text(native)
    result = subprocess.run(["python3", str(probe / "picker-native-lock-check.py")],
                            capture_output=True, text=True, check=False, timeout=ROW_PROBE_TIMEOUT_SECONDS)
    checks += 1
    ok = result.returncode != 0 and "FAIL picker-native-lock-check: missing take_display_lock helper in picker-native.py" in result.stderr
    failures += not ok
    print(("PASS " if ok else "FAIL ") + "missing native lock helper fails with its name")

source = (REPO / "tests/picker-040.sh").read_text()
checks += 1
unused = [scenario for scenario in ["cursor-open", "marked-open", "save-marks", "remember"] if scenario in source]
failures += bool(unused)
print(("FAIL " if unused else "PASS ") + "picker-040 contains only reachable scenarios" + (": " + ", ".join(unused) if unused else ""))

for name in ["picker-hunt", "picker-040"]:
    source = (REPO / "tests" / (name + ".qml")).read_text()
    # Sample input: win.cursorIndex = win.rows.findIndex(...) + win.held precedes win.focusView().
    line = next(line for line in source.splitlines() if "win.rows.findIndex" in line)
    begin = source.index(line)
    end = source.index("                win.focusView()", begin)
    locate = source[begin:end]
    with tempfile.TemporaryDirectory(prefix="picker-missing-row-") as scratch:
        probe = Path(scratch) / "missing-row.qml"
        probe.write_text("""import QtQuick
Item {
    id: root
    property var win: ({rows: [{n: "z.txt"}], held: HELD_OFFSET, cursorIndex: 0})
    property bool finished: false
    property bool named: false
    property bool accepted: false
    function check(label, got, want) {
        named = label.indexOf("missing row a.txt") >= 0 && got !== want
    }
    function finish() { finished = true }
    function locate() {
LOCATE
        accepted = true
    }
    Component.onCompleted: {
        locate()
        var ok = finished && named && !accepted
        console.log((ok ? "PASS " : "FAIL ") + "missing row a.txt held=" + win.held + " finished=" + finished + " named=" + named + " accepted=" + accepted)
        Qt.exit(ok ? 0 : 1)
    }
}
""".replace("HELD_OFFSET", str(HELD_ROW_OFFSET)).replace("LOCATE", locate))
        result = subprocess.run(["timeout", str(ROW_PROBE_TIMEOUT_SECONDS), "qml6", str(probe)],
                                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1"),
                                capture_output=True, text=True, check=False, timeout=ROW_PROBE_TIMEOUT_SECONDS + ROW_PROBE_GRACE_SECONDS)
        checks += 1
        ok = result.returncode == 0 and "PASS missing row a.txt" in result.stderr
        failures += not ok
        print(("PASS " if ok else "FAIL ") + name + " missing row fails before held offset")
        if not ok:
            print(result.stderr.strip())

print(f"picker-runner-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
