#!/usr/bin/env python3
"""Fault injection into picker phase classification and selection output capture."""
from pathlib import Path
import os
import re
import signal
import stat
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
CRASH_EXIT = 128 + signal.SIGSEGV
ROW_PROBE_TIMEOUT_SECONDS = 5
ROW_PROBE_GRACE_SECONDS = 1
HELD_ROW_OFFSET = 60
CHANGED_BASE_FIXTURE_FILES = 13
CHANGED_WIDE_EXTRA_FILES = 201
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
        for fault in ["timeout", "crash", "sigpipe", "missing-done", "clean-noisy"]:
            producer = "print('PICKER_HUNT DONE 1 checks, 0 failed', flush=True)"
            if fault == "timeout":
                command = ["timeout", TIMEOUT_SECONDS, "python3", "-c", "import time; " + producer + "; time.sleep(" + str(PRODUCER_SLEEP_SECONDS) + ")"]
            elif fault == "crash":
                command = ["python3", "-c", producer + "; raise SystemExit(" + str(CRASH_EXIT) + ")"]
            else:
                prefix = "PICKER_HUNT DONE 1 checks, 0 failed\n"
                if fault == "sigpipe":
                    prefix = "PICKER_HUNT FAIL injected\n" + prefix
                elif fault == "missing-done":
                    prefix = ""
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
            scenarios = ["cursor-open", "all"] if name == "picker-hunt" and fault == "clean-noisy" else ["cursor-open" if name == "picker-hunt" else "path"]
            if name == "picker-hunt" and fault in ["sigpipe", "missing-done"]:
                scenarios = ["all"]
            for scenario in scenarios:
                verdict = subprocess.run(["bash", "-c", script, "check", scratch,
                                          scenario, str(result.returncode), name],
                                         capture_output=True, text=True, check=False)
                rejected = verdict.returncode != 0
                wanted = fault != "clean-noisy"
                status_line = fault not in ["timeout", "crash"] or ("FAIL " in verdict.stdout and "exit=" + str(result.returncode) in verdict.stdout)
                if fault == "sigpipe":
                    status_line = "FAIL picker phase default list " + scenario + " reported failed checks" in verdict.stdout
                elif fault == "missing-done":
                    status_line = "FAIL picker hunt did not reach a clean verdict" in verdict.stdout
                checks += 1
                ok = rejected == wanted and status_line
                failures += not ok
                print(("PASS " if ok else "FAIL ") + name + " " + fault + " scenario=" + scenario + " producer=" + str(result.returncode)
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
scratch=$(dirname "$1")
if [ -f "$scratch/.flea-test-sandbox" ]; then marked=marked; else marked=unmarked; fi
printf 'selection scratch %s %s\\n' "$marked" "$scratch"
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
        # Sample input: selection scratch marked /home/flea-sandbox/flea-picker-selection.AbC123
        scratch_line = re.search(r"selection scratch (marked|unmarked) (\S+)", result.stdout)
        checks += 1
        ok = bool(scratch_line) and scratch_line.group(1) == "marked" and not Path(scratch_line.group(2)).exists()
        failures += not ok
        print(("PASS " if ok else "FAIL ") + "F49 picker-selection scratch is marked and removed, exit=" + str(status)
              + " saw=" + (" ".join(scratch_line.groups()) if scratch_line else "none"))

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

with tempfile.TemporaryDirectory(prefix="picker-missing-import-") as scratch:
    probe = Path(scratch)
    (probe / "picker-native-lock-check.py").write_text((REPO / "tests/picker-native-lock-check.py").read_text())
    # Sample input: import re supplies decimal-fd validation in the production native runner.
    native = (REPO / "tests/picker-native.py").read_text().replace("import re\n", "")
    (probe / "picker-native.py").write_text(native)
    result = subprocess.run(["python3", str(probe / "picker-native-lock-check.py")],
                            capture_output=True, text=True, check=False, timeout=ROW_PROBE_TIMEOUT_SECONDS)
    checks += 1
    ok = result.returncode != 0 and "name 're' is not defined" in result.stdout + result.stderr
    failures += not ok
    print(("PASS " if ok else "FAIL ") + "F27 missing production re import fails native lock checker")

source = (REPO / "tests/picker-040.sh").read_text()
checks += 1
unused = [scenario for scenario in ["cursor-open", "marked-open", "save-marks", "remember"] if scenario in source]
failures += bool(unused)
print(("FAIL " if unused else "PASS ") + "picker-040 contains only reachable scenarios" + (": " + ", ".join(unused) if unused else ""))

source = (REPO / "tests/picker-hunt.qml").read_text()
# Sample input: root.check("Ctrl+A marks shown files", win.marks.length, scenario === "all-wide" ? root.baseFixtureFiles + root.wideExtraFiles : root.baseFixtureFiles).
count_line = next(line for line in source.splitlines() if 'root.check("Ctrl+A marks ' in line)
expectation = count_line.split("win.marks.length, ", 1)[1].rsplit(")", 1)[0]
for scenario in ["all", "all-wide"]:
    with tempfile.TemporaryDirectory(prefix="picker-fixture-count-") as scratch:
        probe = Path(scratch) / "fixture-count.qml"
        probe.write_text('''import QtQuick
Item {
    Component.onCompleted: {
        var root = {baseFixtureFiles: BASE_FILES, wideExtraFiles: EXTRA_FILES}
        var scenario = "SCENARIO"
        var got = EXPECTATION
        var want = root.baseFixtureFiles + (scenario === "all-wide" ? root.wideExtraFiles : 0)
        console.log((got === want ? "PASS " : "FAIL ") + "F30 fixture count " + scenario + " got=" + got + " expected=" + want)
        Qt.exit(got === want ? 0 : 1)
    }
}
'''.replace("BASE_FILES", str(CHANGED_BASE_FIXTURE_FILES)).replace("EXTRA_FILES", str(CHANGED_WIDE_EXTRA_FILES))
            .replace("SCENARIO", scenario).replace("EXPECTATION", expectation))
        result = subprocess.run(["timeout", str(ROW_PROBE_TIMEOUT_SECONDS), "qml6", str(probe)],
                                env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1"),
                                capture_output=True, text=True, check=False, timeout=ROW_PROBE_TIMEOUT_SECONDS + ROW_PROBE_GRACE_SECONDS)
        checks += 1
        ok = result.returncode == 0 and "PASS F30 fixture count" in result.stderr
        failures += not ok
        print(("PASS " if ok else "FAIL ") + "F30 " + scenario + " expectation follows changed fixture counts")
        if not ok:
            print(result.stderr.strip())

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

# Sample input: ui/PickerChrome.qml:72 `opacity: available ? 1 : 0.55` names no token for the dim.
bare = []
for path in sorted((REPO / "ui").glob("Picker*.qml")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r"\bopacity:.*\d*\.\d", line):
            bare.append(path.name + ":" + str(number))
chrome = (REPO / "ui/PickerChrome.qml").read_text()
checks += 1
ok = not bare and "opacity: available ? 1 : Theme.disabledOpacity" in chrome
failures += not ok
print(("PASS " if ok else "FAIL ") + "F39 picker dims an unavailable control through Theme.disabledOpacity"
      + (": bare opacity literal at " + ", ".join(bare) if bare else ""))

# Sample input: a rows fixture `"p": <mode digits>` or a `SystemExit(<status digits>)` with no named constant.
for name, value, what in (("picker-focus-helper.py", stat.S_IFREG | 0o644, "regular-file mode"),
                          ("picker-runner-check.py", 128 + signal.SIGSEGV, "crash status")):
    lines = (REPO / "tests" / name).read_text().splitlines()
    bare = [str(number) for number, line in enumerate(lines, 1)
            if re.search(r"(?<![\w.])" + str(value) + r"(?![\w.])", line) and not re.match(r"[A-Z_]+ = ", line)]
    checks += 1
    failures += bool(bare)
    print(("FAIL " if bare else "PASS ") + "F47 " + name + " names its " + what
          + (": bare literal at line " + ", ".join(bare) if bare else ""))

# Sample input: `try:r=json.load(open(sys.argv[1]))` directly under `# Sample input: {"response": 0}`.
lines = (REPO / "tests/picker-hunt.sh").read_text().splitlines()
bare = [str(number) for number, line in enumerate(lines, 1)
        if "json.load(" in line and not re.match(r"\s*#\s*Sample input:", lines[number - 2])]
checks += 1
failures += bool(bare)
print(("FAIL " if bare else "PASS ") + "F48 every picker-hunt inline JSON parser has a sample-input comment above it"
      + (": missing above line " + ", ".join(bare) if bare else ""))

# Sample input: `case "$name" in picker-040) continue ;; esac` exempts a suite that neither list names.
run_all = (REPO / "tests/run-all.sh").read_text()
listed = re.search(r'^headless=".*\bpicker-040\b', run_all, re.M) or re.search(r"^picker-040\|", run_all, re.M)
exempt = re.search(r'case "\$name" in[^\n]*picker-040', run_all)
checks += 1
ok = bool(listed) and not exempt
failures += not ok
print(("PASS " if ok else "FAIL ") + "F45 run-all names picker-040 in a list and exempts nothing"
      + ("" if listed else ": in neither list") + (": a case clause exempts it" if exempt else ""))

# Sample input: `win.marks = [{path: ...}]` hands the picker a selection that a one-file request never lets a user make.
hunt_qml = (REPO / "tests/picker-hunt.qml").read_text()
assigned = [str(number) for number, line in enumerate(hunt_qml.splitlines(), 1) if re.search(r"\bwin\.marks\s*=[^=]", line)]
multiple_validate = re.search(r"refuse-validate\) multiple=true", (REPO / "tests/picker-hunt.sh").read_text())
checks += 1
ok = not assigned and bool(multiple_validate)
failures += not ok
print(("PASS " if ok else "FAIL ") + "F46 refuse-validate marks through Space in a multiple request"
      + (": win.marks assigned at line " + ", ".join(assigned) if assigned else "")
      + ("" if multiple_validate else ": the request is not multiple"))

print(f"picker-runner-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
