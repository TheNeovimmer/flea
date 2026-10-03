"""Drive the real capture branches with bad and good state, without native effects."""
import ast
import contextlib
import io
import json
from pathlib import Path
import re
import signal
import subprocess
import sys
import tomllib
from types import SimpleNamespace

CONTROL_TIMEOUT_SECONDS = 10
PROCESS_WAIT_SECONDS = 5

scratch, repo = map(Path, sys.argv[1:3])
groups = sys.argv[3:] or ["G1", "G2", "G3", "G4", "G7"]
picker_file = repo / "tests/ui-captures-sweep-picker.py"
# Sample input: def wait(label, predicate): in the picker capture script.
picker_tree = ast.parse(picker_file.read_text())
picker_try = next(node for node in picker_tree.body if isinstance(node, ast.Try))


def compiled(nodes):
    return compile(ast.Module(body=nodes, type_ignores=[]), str(picker_file), "exec")


def picker_case(label, mode, patch):
    evidence = scratch / label
    evidence.mkdir()
    world = {"view": "list", "marks": ["alpha.txt"], "marksBusy": False, "body": 14,
             "themeLoaded": True, "themeForeground": palette["foreground"].lower()}
    clock = SimpleNamespace(now=0)

    def sleep(seconds):
        clock.now += seconds

    def press(*keys):
        world["view"] = "grid" if "3" in keys else "list"
        if world["view"] == mode:
            world.update(patch)

    def run(arguments):
        if arguments[0] == "omarchy-drive":
            Path(arguments[2]).write_bytes(b"synthetic PNG")
            return ""
        assert arguments[0] == "magick", arguments
        return "1040x760"

    namespace = {"state": lambda: dict(world), "press": press, "run": run,
                 "evidence": evidence, "title": "Owned test picker", "json": json, "re": re,
                 "Path": Path, "tomllib": tomllib, "theme_home": theme_home,
                 "expected_foreground": palette["foreground"].lower(),
                 "time": SimpleNamespace(monotonic=lambda: clock.now, sleep=sleep),
                 "GLib": SimpleNamespace(MainContext=SimpleNamespace(default=lambda: SimpleNamespace(pending=lambda: False)))}
    helpers = [node for node in picker_tree.body if isinstance(node, ast.FunctionDef)
               and node.name in ("wait", "capture_state", "fixture_foreground")]
    constants = [node for node in picker_tree.body if isinstance(node, ast.Assign)
                 and isinstance(node.value, ast.Constant)
                 and all(isinstance(target, ast.Name) and target.id.isupper() for target in node.targets)]
    exec(compiled(constants + helpers), namespace)
    if "fixture_foreground" in namespace:
        assert namespace["fixture_foreground"](theme_home) == palette["foreground"].lower()
    loop = next(node for node in picker_try.body if isinstance(node, ast.For))
    error = None
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            exec(compiled([loop]), namespace)
    except AssertionError as refused:
        error = str(refused)
    manifest = evidence / "manifest.tsv"
    entries = manifest.read_text().splitlines() if manifest.exists() else []
    target = f"sweep-picker-{mode}-selected"
    if patch:
        assert error, f"{label}: bad state accepted into manifest: {entries}"
        assert not any(entry.startswith(target) for entry in entries), (label, entries)
        assert not (evidence / f"{target}.png").exists(), label
        if "marks" in patch or "marksBusy" in patch:
            assert "marksBusy" in error and "marks" in error, error
        return
    assert error is None, error
    assert len(entries) == 2, entries
    for view in ("list", "grid"):
        # Sample input: {"marksBusy":false,"marks":["alpha.txt"],"themeLoaded":true}.
        observed = json.loads((evidence / f"sweep-picker-{view}-selected.json").read_text())
        assert not observed["marksBusy"] and len(observed["marks"]) == 1, observed
        assert observed["themeLoaded"] and observed["themeForeground"] == palette["foreground"].lower(), observed


def picker_controls(group):
    patches = [{"marks": []}, {"marksBusy": True}, {"marks": ["alpha", "beta"]}] if group == "G1" else [
        {"themeLoaded": False}, {"themeForeground": "#ffffff"}]
    for mode in ("list", "grid"):
        for index, patch in enumerate(patches):
            picker_case(f"{group}-{mode}-bad-{index}", mode, patch)
    picker_case(f"{group}-good", "grid", {})
    print(f"CAPSWEEP_CONTROLS {group} refused={len(patches) * 2} accepted=1")


def shell_case(group, accepted):
    root = scratch / f"{group}-{'good' if accepted else 'bad'}"
    for directory in ("views", "previews", "evidence", "run"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    (root / "views/a.txt").write_text("source\n")
    (root / "previews/notes.md").write_text("# Release notes\n\nBody\n")
    (root / "run/flea-second.log").touch()
    prelude = r'''set -euo pipefail
repo=$1
sweep_root=$2
good=$3
evidence_dir="$sweep_root/evidence"
run_root="$sweep_root/run"
run_log="$sweep_root/run.log"
real_foreground='#dfe8e0'
. "$repo/tests/ui-captures-sweep.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sleep() { SECONDS=$((SECONDS + 1)); }
settle() { :; }
assert_theme() { :; }
token_of() { printf '14\n'; }
magick() { printf '1040x760'; }
shot() { printf 'synthetic PNG\n' > "$evidence_dir/$1.png"; }
omarchy-drive() { [[ "$1" == shot ]] || fail 'unexpected drive call'; printf 'synthetic PNG\n' > "$2"; }
'''
    if group == "G3":
        driver = (repo / "tests/ui.sh").read_text()
        # Sample input: xwdrag_glide() { followed by xwdrag_drag() { in tests/ui.sh.
        glide = driver.split("xwdrag_glide() {", 1)[1].split("\nxwdrag_drag() {", 1)[0]
        stubs = r'''
sweep_launch() { :; }
flea_pid() { printf '101\n'; }
xwdrag_qsid() { printf '%s\n' "$1"; }
xwdrag_launch_second() { XW_SECOND_PID=202; XW_SECOND_ID=202; }
xwdrag_cleanup() { :; }
case_xwdrag_cleanup() { :; }
xwdrag_signal_cleanup() { :; }
xwdrag_kill_second() { :; }
kill_flea() { :; }
xwdrag_focus() { :; }
xwdrag_key() { :; }
xwdrag_addr() { printf '0x%s\n' "$1"; }
xwdrag_geometry() { if [[ "$1" == 101 ]]; then printf '0 0 400 600\n'; else printf '400 0 400 600\n'; fi; }
xwdrag_qs() {
    case "$2" in
        tokens) printf 'baseSize=14\nother=0\n' ;;
        bodyPx) printf '14\n' ;;
        themeLoaded) printf 'true\n' ;;
        themeForeground) printf '#dfe8e0\n' ;;
        selectionCount) printf '1\n' ;;
        listingDropActive) [[ "$1" == 202 ]] || fail 'drag read on A'; printf '%s\n' "$good" ;;
        *) fail "unexpected IPC: $2" ;;
    esac
}
xwdrag_row_point() { printf '100 100\n'; }
xwdrag_floor_point() { printf '500 500\n'; }
hyprctl() {
    case "$1" in
        monitors) printf '[{"focused":true,"x":0,"y":0,"width":800,"height":600,"scale":1}]\n' ;;
        clients) printf '[{"pid":101,"address":"0x101","floating":true},{"pid":202,"address":"0x202","floating":true}]\n' ;;
        dispatch) printf 'ok\n' ;;
        cursorpos) cat "$sweep_root/pointer" ;;
        *) fail "unexpected hyprctl: $1" ;;
    esac
}
ydotool() {
    if [[ "$1" == mousemove ]]; then
        # Sample input: 100 100, the simulated desktop pointer position.
        read -r cursor_x cursor_y < "$sweep_root/pointer"
        printf '%s %s\n' "$((cursor_x + $3))" "$((cursor_y + $5))" > "$sweep_root/pointer"
    elif [[ "$1" == click ]]; then
        printf '%s\n' "$2" >> "$sweep_root/buttons"
    else
        fail "unexpected ydotool: $1"
    fi
}
printf '0 0\n' > "$sweep_root/pointer"
'''
        script = prelude + stubs + "\nxwdrag_glide() {" + glide + "\nsweep_windows\n"
        name = "windows-drag-held"
    else:
        capture = (repo / "tests/ui-captures-sweep.sh").read_text()
        # Sample input: elif [[ "$tag" == markdown ]]; then, ending at its matching fi.
        branch = capture.split('elif [[ "$tag" == markdown ]]; then\n', 1)[1].split("\n        fi", 1)[0]
        stubs = r'''
overlay_mode=rendered
key() { [[ "$1" == r ]] || fail 'unexpected key'; if [[ "$good" == true ]]; then overlay_mode=source; fi; }
ipc() {
    case "$1" in
        bodyPx) printf '14\n' ;;
        previewState) printf 'ready\n' ;;
        previewMarkdownView) printf '%s\n' "$overlay_mode" ;;
        columnMarkdownText|previewText) cat "$sweep_root/previews/notes.md" ;;
        *) fail "unexpected reader: $1" ;;
    esac
}
'''
        script = prelude + stubs + branch + "\n"
        name = "quicklook-markdown-source"
    script_file = root / "probe.sh"
    script_file.write_text(script)
    result = subprocess.run(["bash", str(script_file), str(repo), str(root), str(accepted).lower()],
                            capture_output=True, text=True, timeout=CONTROL_TIMEOUT_SECONDS)
    manifest = root / "evidence/manifest.tsv"
    if accepted:
        assert result.returncode == 0, result.stdout + result.stderr
        assert manifest.read_text() == f"sweep-{name}\t1040x760\n"
    else:
        assert result.returncode != 0, f"{group}: bad state accepted: {result.stdout}"
        assert "capsweep:" in result.stderr, result.stderr
        assert not manifest.exists() and not (root / f"evidence/sweep-{name}.png").exists()
    if group == "G3":
        assert (root / "buttons").read_text().splitlines() == ["0x40", "0x80"], "held button not released"


def cleanup_controls():
    for gone in (False, True):
        calls = []

        def killpg(pid, sig):
            calls.append((pid, sig))
            if gone:
                raise ProcessLookupError()

        process = SimpleNamespace(pid=101, poll=lambda: 0, wait=lambda **kwargs: 0)
        cleanup = next(node for node in picker_try.finalbody if isinstance(node, ast.For))
        namespace = {"processes": [process], "os": SimpleNamespace(killpg=killpg),
                     "signal": signal, "subprocess": subprocess, "PROCESS_WAIT_SECONDS": PROCESS_WAIT_SECONDS}
        exec(compiled([cleanup]), namespace)
        assert calls == [(process.pid, signal.SIGTERM)], calls
    print("CAPSWEEP_CONTROLS G4 exited-leader=1 gone-group=1")


theme_home = scratch / "theme-home"
theme_path = theme_home / ".local/state/omarchy/current/theme/colors.toml"
theme_path.parent.mkdir(parents=True)
theme_path.write_bytes((repo / "tests/fixtures/cool-dawn/colors.toml").read_bytes())
# Sample input: foreground = "#DFE8E0" in the installed colors.toml.
palette = tomllib.loads(theme_path.read_text())
failures = []
for group in groups:
    try:
        if group in ("G1", "G2"):
            picker_controls(group)
        elif group == "G4":
            cleanup_controls()
        else:
            shell_case(group, False)
            shell_case(group, True)
            print(f"CAPSWEEP_CONTROLS {group} refused=1 accepted=1")
    except AssertionError as error:
        failures.append(group)
        print(f"FAIL: {group}: {error}")
print(f"CAPSWEEP_CONTROLS groups={len(groups)} failed={len(failures)}")
sys.exit(bool(failures))
