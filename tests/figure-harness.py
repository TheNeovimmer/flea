# Execute the figure suite's real shell fragments with controlled lower-layer failures.
import json
import os
import pathlib
import re
import selectors
import signal
import shutil
import subprocess
import sys
import tempfile

tree = pathlib.Path(__file__).resolve().parents[1]
script = (tree / "tests/markdown-figures.sh").read_text()
checks = 0
failures = 0
# Every isolated shell fragment and fixture engine has a short termination bound.
FRAGMENT_BOUND_SECONDS = 10


def check(passed, label):
    global checks, failures
    checks += 1
    failures += not passed
    print(("PASS " if passed else "FAIL ") + label)


def section(start, end):
    return script.split(start, 1)[1].split(end, 1)[0]


with tempfile.TemporaryDirectory(prefix="flea-figure-harness-") as scratch:
    box = pathlib.Path(scratch)
    binary = box / "flea"
    binary.write_text('''#!/bin/sh
if [ "$FIG_MODE" = silent ]; then
    exit 127
fi
if [ "$FIG_MODE" = wrong ]; then
    echo "flea: unrelated refusal" >&2
    exit 127
fi
if [ "$FIG_MODE" = namespace ]; then
    echo "bwrap: No permissions to create new namespace" >&2
    exit 1
fi
if [ "$FIG_MODE" = broken ]; then
    echo "figure renderer exploded" >&2
    exit 1
fi
if [ "$FIG_MODE" = empty ]; then
    exit 0
fi
if [ "$FIG_MODE" = good ]; then
    echo '{"id":1,"svg":"<svg/>"}'
    exit 0
fi
if ! command -v bwrap >/dev/null || ! command -v prlimit >/dev/null; then
    echo "flea: the figure helper needs bwrap and prlimit, and one of them is missing" >&2
    exit 127
fi
echo "flea: the figure helper needs quickjs-ng at $FLEA_QJS, and it is missing" >&2
exit 127
''')
    binary.chmod(0o755)
    qjs = box / "qjs"
    qjs.write_text("#!/bin/sh\nprintf 'selected direct engine\\n'\n")
    qjs.chmod(0o755)
    tools = box / "tools"
    tools.mkdir()
    for name in ("bwrap", "prlimit"):
        (tools / name).write_text("#!/bin/sh\nexit 0\n")
        (tools / name).chmod(0o755)
    for name in ("mkdir", "ln", "cmp", "wc"):
        (tools / name).symlink_to(shutil.which(name))
    (box / "empty-path").mkdir()

    def run(body, mode="refusal", **extra):
        env = dict(os.environ, FIG_MODE=mode, test_root=str(box), fleabin=str(binary), qjs=str(qjs), **extra)
        return subprocess.run(["/bin/bash", "-uc", body], cwd=tree, env=env,
                              capture_output=True, text=True, timeout=FRAGMENT_BOUND_SECONDS)

    ui_setup = section('cd "$(dirname "$0")/.." || exit 1\n', '\nfleabin=')
    exported_ui = '\n/bin/sh -c \'printf "%s\\n" "$FLEA_UI"\''
    result = run(ui_setup + exported_ui, FLEA_UI="")
    check(result.returncode == 0 and result.stdout.strip() == str(tree / "ui"),
          "PSS fix suite exports the candidate UI by default")
    chosen_ui = str(box / "caller-ui")
    result = run(ui_setup + exported_ui, FLEA_UI=chosen_ui)
    check(result.returncode == 0 and result.stdout.strip() == chosen_ui,
          "PSS fix suite preserves the caller's UI override")

    start_binary = box / "start-flea"
    captured_ui = box / "captured-ui"
    start_pid = box / "start.pid"
    # Larger than the startup check's bounded diagnostic excerpt.
    DIAGNOSTIC_FIXTURE_CHARS = 8192
    start_binary.write_text(f'''#!{sys.executable}
import os, pathlib, signal, sys
pathlib.Path({str(captured_ui)!r}).write_text(os.environ.get("FLEA_UI", ""))
print("helper stdout cause", flush=True)
print("helper stderr cause", file=sys.stderr, flush=True)
if os.environ.get("FIG_START_MODE") == "hang":
    pathlib.Path({str(start_pid)!r}).write_text(str(os.getpid()))
    signal.pause()
print("x" * {DIAGNOSTIC_FIXTURE_CHARS} + "UNBOUNDED_STDOUT_TAIL")
print("x" * {DIAGNOSTIC_FIXTURE_CHARS} + "UNBOUNDED_STDERR_TAIL", file=sys.stderr)
''')
    start_binary.chmod(0o755)
    def startup(ui=None, mode="failed"):
        env = dict(os.environ, FIG_START_MODE=mode)
        if ui is None:
            env.pop("FLEA_UI", None)
        else:
            env["FLEA_UI"] = ui
        return subprocess.run([sys.executable, str(tree / "tests/figure-helper-start.py"), str(start_binary)],
                              cwd=tree, env=env, capture_output=True,
                              text=True, timeout=FRAGMENT_BOUND_SECONDS)
    result = startup()
    check(captured_ui.read_text() == str(tree / "ui"),
          "PSS fix helper startup exports the candidate UI by default")
    check(result.returncode != 0 and "helper stdout cause" in result.stdout
          and "helper stderr cause" in result.stdout,
          "PSS fix failed startup prints captured stdout and stderr")
    check("UNBOUNDED_STDOUT_TAIL" not in result.stdout and "UNBOUNDED_STDERR_TAIL" not in result.stdout,
          "PSS fix startup diagnostic excerpts stay bounded")
    startup(chosen_ui)
    check(captured_ui.read_text() == chosen_ui,
          "PSS fix helper startup preserves the caller's UI override")
    result = startup(mode="hang")
    check(result.returncode != 0 and "FAIL helper did not exit within" in result.stdout
          and "helper stdout cause" in result.stdout and "helper stderr cause" in result.stdout,
          "PSS fix startup timeout reports its bound and both captured streams")
    result = subprocess.run(["pgrep", "-F", str(start_pid)], capture_output=True, text=True,
                            timeout=FRAGMENT_BOUND_SECONDS)
    check(result.returncode == 1 and not result.stdout,
          f"r3 startup fixture pid={start_pid.read_text()} reaped (pgrep exit={result.returncode})")

    pss_checks = '# The GUI memory claim:' + section('# The GUI memory claim:', '\nprintf \'MARKDOWN_FIGURES %s')
    def memory_samples(before, formulas, diagrams, stamps=(1, 2, 3, 4), anonymous=None):
        phases = (("before", before), ("formulas", formulas), ("diagrams", diagrams), ("idle", before))
        anonymous = anonymous if anonymous is not None else (before, formulas, diagrams, before)
        output = "\n".join(f"MARKDOWN_FIGURES FIGPSS phase={phase} pss_kb={value}"
                           + (f" read_seq={stamp}" if stamp is not None else "")
                           + f" anonymous_kb={anon}"
                           for (phase, value), stamp, anon in zip(phases, stamps, anonymous))
        output += "\nMARKDOWN_FIGURES FIGHELPER rss_peak_kb=41140"
        return run(pss_checks, output=output, verdict="0")
    result = memory_samples(52877, 52877, 52877)
    check(result.returncode == 0, "r3 equal PSS samples with fresh read stamps pass")
    for index, phase in enumerate(("before", "formulas", "diagrams", "idle")):
        stamps = [1, 2, 3, 4]
        stamps[index] = None
        result = memory_samples(52877, 52878, 52879, stamps)
        check(result.returncode != 0 and f"FAIL no FIGPSS {phase} read stamp" in result.stdout,
              f"r3 a missing {phase} read stamp fails")
    for stamps in ((1, 1, 3, 4), (1, 2, 1, 4), (1, 2, 3, 3)):
        result = memory_samples(52877, 52878, 52879, stamps)
        check(result.returncode != 0 and "read stamp is stale" in result.stdout,
              f"r3 cached or backward read stamps {stamps} fail")
    result = memory_samples(52877, 52878, 52879)
    check(result.returncode == 0, "PSS fix fresh render-phase samples within budget pass")
    result = memory_samples(52877, 63118, 52879)
    check(result.returncode != 0 and "FAIL formulas Anonymous exceeds before" in result.stdout,
          "PSS fix fresh formula samples still enforce the existing budget")
    result = memory_samples(52877, 52878, 63118)
    check(result.returncode != 0 and "FAIL diagrams Anonymous exceeds before" in result.stdout,
          "PSS fix fresh diagram samples still enforce the existing budget")
    memory_before_kb = 52877
    memory_limit_kb = 10240
    over_limit_kb = memory_before_kb + memory_limit_kb + 1
    result = memory_samples(memory_before_kb, over_limit_kb, over_limit_kb,
                            anonymous=(memory_before_kb,) * 4)
    check(result.returncode == 0, "G7 PSS jumps past 10240 kB while Anonymous is flat pass")
    for index, phase in ((1, "formulas"), (2, "diagrams")):
        anonymous = [memory_before_kb] * 4
        anonymous[index] = over_limit_kb
        result = memory_samples(memory_before_kb, memory_before_kb, memory_before_kb,
                                anonymous=anonymous)
        check(result.returncode != 0 and f"FAIL {phase} Anonymous exceeds before" in result.stdout,
              f"G7 flat PSS with {phase} Anonymous growth past 10240 kB fails")
    result = memory_samples(memory_before_kb, memory_before_kb, memory_before_kb,
                            anonymous=(memory_before_kb, "", memory_before_kb, memory_before_kb))
    check(result.returncode != 0 and "FAIL no FIGPSS formulas Anonymous value" in result.stdout,
          "G7 a missing Anonymous value fails")

    refusal = section("# A missing engine", "# Byte identity")
    for mode in ("silent", "wrong"):
        result = run(refusal, mode)
        check(result.returncode != 0, "F1 rejects " + mode + " missing-engine refusal")
    result = run(refusal, PATH=str(tools))
    check(result.returncode == 0 and "quickjs-ng" in result.stdout and "bwrap and prlimit" in result.stdout,
          "F2 independently exercises engine and sandbox refusal branches")

    probe = f"PROBE_BOUND_SECONDS={FRAGMENT_BOUND_SECONDS}\nprobe_out=" + section("probe_out=", "# One python driver")
    for mode in ("broken", "empty"):
        result = run(probe, mode)
        check(result.returncode != 0, "F3 rejects " + mode + " jail probe")
    result = run(probe, "namespace")
    check(result.returncode == 0 and "user namespaces" in result.stdout,
          "F3 names the detected user-namespace exception")
    check(any("No permissions to create new namespace" in p.read_text() for p in box.glob("*stderr*")),
          "F3 retains jailed probe stderr")
    result = run(probe, "good")
    check(result.returncode == 0 and "driving the jailed helper" in result.stdout,
          "F3 keeps the jail for a successful probe")

    stub = 'cat > "$test_root/stubbin/flea"' + section('cat > "$test_root/stubbin/flea"', 'chmod +x "$test_root/stubbin/flea"')
    (box / "stubbin").mkdir()
    (box / "phase").write_text("answer\n")
    prefix = 'engine=("$qjs" "helper.mjs")\nprintf -v engine_exec \'%q \' "${engine[@]}"\n'
    result = run(prefix + stub + '\n/bin/bash "$test_root/stubbin/flea" --figure-helper')
    check(result.returncode == 0 and "selected direct engine" in result.stdout,
          "F3 QML stub executes the same selected engine")
    check("FLEA_FIG_REAL" not in script, "F3 removes the unread engine export")
    (box / "phase").write_text("hang\n")
    fixture = subprocess.Popen(["/bin/bash", str(box / "stubbin/flea"), "--figure-helper"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        with selectors.DefaultSelector() as ready:
            ready.register(fixture.stdout, selectors.EVENT_READ)
            signaled = bool(ready.select(FRAGMENT_BOUND_SECONDS))
        receipt = fixture.stdout.readline().strip() if signaled else ""
        check(receipt == f"FIGHANG pid={fixture.pid}" and fixture.poll() is None,
              "r3 the shell hang fixture blocks in its own process")
        result = subprocess.run(["pgrep", "-F", str(box / "hang.pid")], capture_output=True,
                                text=True, timeout=FRAGMENT_BOUND_SECONDS)
        check(result.returncode == 0 and result.stdout.strip() == str(fixture.pid),
              f"r3 hanging shell fixture pid={fixture.pid} present (pgrep exit={result.returncode})")
    finally:
        if fixture.poll() is None:
            fixture.kill()
        fixture.communicate(timeout=FRAGMENT_BOUND_SECONDS)
    result = subprocess.run(["pgrep", "-F", str(box / "hang.pid")], capture_output=True,
                            text=True, timeout=FRAGMENT_BOUND_SECONDS)
    check(fixture.returncode == -signal.SIGKILL and result.returncode == 1 and not result.stdout,
          f"r3 shell fixture pid={fixture.pid} killed and reaped (pgrep exit={result.returncode})")

    # Sample input: the drive.py heredoc between <<'EOF' and the next standalone EOF.
    driver = section('cat > "$test_root/drive.py" <<\'EOF\'\n', "\nEOF")
    runner = box / "driver.py"
    runner.write_text(driver)
    duplicate = box / "duplicate.py"
    duplicate.write_text('''#!/usr/bin/python3
import json
import sys
for line in sys.stdin:
    try:
        request = json.loads(line)
        ident = request["id"]
    except ValueError:
        ident = 0
    if ident in (0, 30, 31, 40, 41):
        reply = {"id": ident, "error": "malformed"}
    elif ident == 43:
        reply = {"id": ident, "error": "diagram over 32 KiB"}
    else:
        reply = {"id": ident, "svg": "<svg/>"}
    print(json.dumps(reply))
    if ident == 10:
        print(json.dumps(reply))
''')
    duplicate.chmod(0o755)
    result = subprocess.run([sys.executable, str(runner), str(duplicate), "unused", str(box)],
                            capture_output=True, text=True, timeout=FRAGMENT_BOUND_SECONDS)
    check(result.returncode != 0 and "FAIL every request answered once" in result.stdout,
          "F5 rejects a duplicate reply alongside all expected ids")

    byte_phase = section("# Byte identity", "# FigureService")
    identity_check = 'python3 - "$test_root/node-expected.json"' + section(
        'python3 - "$test_root/node-expected.json"', "\nelse\n")
    expected = box / "node-expected.json"
    actual = box / "node-actual.json"
    expected.write_text('{"frac":"<svg/>"}')
    actual.write_text('{"frac":"<svg!>"}')
    result = run(identity_check + '\nprintf "later suite verdict reached\\n"\n')
    check(result.returncode != 0 and "later suite verdict reached" not in result.stdout,
          "mx2a F12 one changed rendered byte fails the suite")
    check("markdown-figures.sh: FAIL qjs and node disagree on rendered bytes" in result.stdout,
          "mx2a F12 byte mismatch names the failed comparison")
    actual.write_text(expected.read_text())
    result = run(identity_check)
    check(result.returncode == 0 and "PASS qjs renders" in result.stdout,
          "mx2a F12 identical rendered bytes pass")
    result = run(byte_phase + '\nprintf "service phase reached\\n"\n', PATH=str(tools))
    check(result.returncode == 0 and "SKIP node is absent" in result.stdout and "service phase reached" in result.stdout,
          "F11 no-node skip continues to the service and PSS phase")

    if shutil.which("node"):
        alias = box / "checkout&#path"
        alias.symlink_to(tree, target_is_directory=True)
        start = 'cat > "$test_root/identity.mjs"' if 'cat > "$test_root/identity.mjs"' in script else "# Build identity imports"
        generator = (start + section(start, 'node "$test_root/identity.mjs"'))
        result = run(generator, PWD=str(alias))
        theme = box / "theme.json"
        theme.write_text(json.dumps({"bg": "#101315", "fg": "#c0caf5", "bodyPx": 14}))
        if result.returncode == 0:
            result = subprocess.run(["node", str(box / "identity.mjs"), str(theme), str(box / "identity.json")],
                                    capture_output=True, text=True, timeout=FRAGMENT_BOUND_SECONDS)
        check(result.returncode == 0, "F14 identity imports work with & and # in the checkout path")

worker = (tree / "ui/js/FigureWorker.mjs").read_text()
check(not re.search(r"(?m)^[ \t]*//[^\n]*\n[ \t]*//", worker), "F7 worker comment paragraphs occupy one line")
check(not re.search(r"(?m)^#[^\n]*\n#", script[script.index("\n") + 1:]), "F7 shell comment paragraphs occupy one line")
check("depth > 12" not in worker and "/ 2;" not in worker and "* 100) / 100" not in worker,
      "F12 resolver and ex conversion policy numbers have names")
qml = (tree / "tests/markdown-figures.qml").read_text()
check("readonly property int blockedLoopTicks: 1" in qml and "shell.ticks - shell.pendingTicksMark > shell.blockedLoopTicks" in qml,
      "F20 the hanging wait rejects the single coalesced tick of a blocked loop")
# Sample input: "    time.sleep(10)" in a generated Python hang fixture.
check(not re.search(r"(?m)^    time[.]sleep[(]", pathlib.Path(__file__).read_text()) and "hang) sleep" not in script,
      "r3 hang fixtures block without wall-clock sleeps")
reader = (tree / "tests/figure-memory/FigureMemory.qml").read_text()
# Sample input: var kids = memory.readText("/proc/1234/task/1234/children").trim().split(/\s+/);
children_line = next(line for line in reader.splitlines() if '"/children"' in line)
check("Sample input:" in reader.split(children_line, 1)[0].splitlines()[-1],
      "r3 the children parser has a sample-input comment directly above it")
check("Sample input" in reader.split("    function memField", 1)[0].splitlines()[-1],
      "r3 the memory-field parser has a sample-input comment")
check("Date.now()" not in qml and "maxGap" not in qml,
      "mx2a F13 / mx2b F4 QML verdicts use events instead of elapsed time")
service_test = (tree / "tests/js/figureservice.js").read_text()
declaration = "function cacheKeyOf(kind, source, t, display) {"
regex_before = service_test.split("    var functions =", 1)[0].splitlines()[-1]
check("Sample input:" in regex_before and declaration in regex_before,
      "mx2a F14 declaration parser quotes a real service declaration")
start_test = (tree / "tests/figure-helper-start.py").read_text()
check("timeout=HELPER_EXIT_BOUND_SECONDS" in start_test
      and "# A helper that never exits fails the check instead of hanging the suite.\nHELPER_EXIT_BOUND_SECONDS = 5" in start_test,
      "mx2a F16 / mx2b F15 helper startup has a named termination bound")
build = (tree / "tools/vendor-js/build.sh").read_text()
agents = (tree / "AGENTS.md").read_text()
# Sample input: `src/figurehelper.rs` at 210 in the mx2 file-budget paragraph.
budget_paragraph = next(line for line in agents.splitlines() if line.startswith("mx2 renders Markdown maths"))
for path in ("src/figurehelper.rs", "ui/FigureService.qml"):
    recorded = re.search(re.escape(f"`{path}` at ") + r"(\d+)", budget_paragraph)
    actual = len((tree / path).read_text().splitlines())
    check(recorded is not None and int(recorded[1]) == actual,
          f"F24 mx2 records the final {path} line count ({actual})")
helper_source = (tree / "ui/vendor/figure-helper.mjs").read_text()
check(not re.search(r"(?m)^[ \t]*//[^\n]*\n[ \t]*//", helper_source),
      "F26 helper comments keep each constraint on one line")
figure_source = (tree / "ui/MarkdownFigure.qml").read_text()
fallback = figure_source.split("readonly property string fallbackBody:", 1)[1].split("    Rectangle", 1)[0]
check("readonly property int fallbackChars: 2000" in figure_source
      and fallback.count("root.fallbackChars") == 3 and "2000" not in fallback,
      "F27 fallback comparison, slice and remaining count share a named limit")
headless_contract = agents.split("The suites that drive the debug binary", 1)[1].split("Its own `headless=`", 1)[0]
check("needs nothing but a shell" not in headless_contract
      and all(word in headless_contract for word in ("no display, session or hardware", "python3", "Qt", "Quickshell", "quickjs-ng", "refuse loudly", "naming")),
      "mx2b F8 headless contract names its tools and missing-tool refusal")
constraint = build.split("npx esbuild", 1)[0].split("npm ci || exit 1", 1)[1].strip().splitlines()
check(len(constraint) == 1 and len(constraint[0]) <= 140
      and all(word in constraint[0] for word in ("quickjs-ng", "ES modules", "neutral", "es2017", "minified", "exact command")),
      "mx2b F7 bundle constraint fits one comment line")
check("const PERCENT_SCALE = 100;" in worker and "parseFloat(m[2]) / PERCENT_SCALE" in worker,
      "mx2b F12 color-mix percentage conversion uses its named scale")
check("shell.t0 < 5000" not in qml and "shell.maxGap < 2000" not in qml,
      "F12 idle-exit and tick-gap bounds have names")
for marker in ("function parseMix", "function resolveValue", "function inlineClasses", "    svg.replace(/<style>"):
    before = worker.split(marker, 1)[0].splitlines()[-1]
    check("Sample input:" in before, "F13 parser has sample input: " + marker.strip())
print(f"figure-harness: {checks} check(s), {failures} failed")
sys.exit(bool(failures))
