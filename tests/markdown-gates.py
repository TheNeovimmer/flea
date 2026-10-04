#!/usr/bin/env python3
# Execute the runner's prerequisite refusals and the capture's Source gate without starting Qt.
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PROBE_TIMEOUT_SECONDS = 10
REPO = Path(__file__).resolve().parent.parent
failures = 0
checks = 0


def check(ok, label):
    global failures, checks
    checks += 1
    if not ok:
        failures += 1
    print(("ok " if ok else "FAIL ") + label)


with tempfile.TemporaryDirectory(prefix="md-gates-", dir=os.environ.get("TMPDIR")) as tmp:
    root = Path(tmp)
    tree = root / "checkout"
    for directory in ["tests", "tools", "target/debug", "bin"]:
        (tree / directory).mkdir(parents=True)
    for directory in ["ui/boot/Commons", "ui/boot/Ui"]:
        (tree / directory).mkdir(parents=True)
    for name in ["markdown-figures-render.sh", "markdown-figures-render.qml", "markdown-figures-render.js"]:
        shutil.copyfile(REPO / "tests" / name, tree / "tests" / name)
    shutil.copyfile(REPO / "tools/flea-sandbox-guard", tree / "tools/flea-sandbox-guard")
    for name in ["dirname", "mkdir", "chmod", "ln", "readlink", "cp", "realpath", "rm", "env", "timeout", "grep", "head", "cat"]:
        (tree / "bin" / name).symlink_to(shutil.which(name))
    qs = tree / "bin/qs"
    qs.write_text('#!/bin/sh\nprintf "%s\\n" "$FLEA_UI" > "$MD_GATE_TRACE"\nexit 1\n')
    qs.chmod(0o755)
    flea = tree / "target/debug/flea"
    qjs = tree / "bin/qjs"
    trace = root / "trace"
    env = dict(os.environ, PATH=str(tree / "bin"), HOME=str(root / "operator"),
               FLEA_FIXTURE_ROOT=str(root / "fixtures"), FLEA_QJS="",
               FLEA_UI=str(root / "other-ui"), MD_GATE_TRACE=str(trace))

    def runner():
        trace.unlink(missing_ok=True)
        return subprocess.run(["/bin/bash", str(tree / "tests/markdown-figures-render.sh")],
                              env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              timeout=PROBE_TIMEOUT_SECONDS)

    flea.write_text('#!/bin/sh\nprintf \'{"svg":"<svg/>"}\\n\'\n')
    flea.chmod(0o755)
    result = runner()
    check(result.returncode != 0 and "missing qjs" in result.stdout and not trace.exists(),
          "md3z F1 missing qjs refused before any Qt run")
    qjs.write_text("#!/bin/sh\nexit 0\n")
    qjs.chmod(0o755)
    flea.unlink()
    result = runner()
    check(result.returncode != 0 and "missing flea binary" in result.stdout and not trace.exists(),
          "md3z F1 missing flea binary refused before any Qt run")
    flea.write_text('#!/bin/sh\nprintf \'{"svg":"<svg/>"}\\n\'\n')
    flea.chmod(0o755)
    result = runner()
    if not trace.exists():
        print(result.stdout)
    check(trace.exists() and trace.read_text().strip() == str(tree / "ui"),
          "md3t F1 inherited FLEA_UI replaced with checkout ui")

    fixture = root / "capture"
    fixture.mkdir()
    capture = root / "capture.sh"
    # Sample input: ipc columnMarkdownView returns "rendered" or "source"; previewOpen follows Space and Escape.
    capture.write_text('''set -u
fixture_root=$MD_GATE_FIXTURE
opened=false
sandbox_scratch() { mkdir -p "$1"; }
launch() { :; }
wait_listing() { :; }
goto_row() { :; }
row_index_of() { echo 0; }
settle() { :; }
shot() { printf 'SHOT %s\\n' "$1"; }
switch_view() { :; }
kill_flea() { :; }
window_box() { echo '0 0 800 600'; }
omarchy-drive() { :; }
ydotool() { :; }
XDG_RUNTIME_DIR=$MD_GATE_FIXTURE
seq() { echo 1; }
sleep() { :; }
fail() {
    printf 'REFUSED %s\\n' "$*"
    exit 1
}
key() {
    case "$*" in
        "-k Space") opened=true ;;
        "-k Escape") opened=false ;;
    esac
}
ipc() {
    case "$1" in
        previewOpen) echo "$opened" ;;
        previewFigures) echo '1=ready,2=ready,3=ready,4=ready,5=failed' ;;
        columnMarkdownView) echo "$MD_GATE_COLUMN_VIEW" ;;
        previewSurfaceRect) echo '40 40 700 500' ;;
        chromeHeight) echo 20 ;;
    esac
}
. "$MD_GATE_CAPTURE"
case_cap_markdown
''')
    env = dict(os.environ, MD_GATE_FIXTURE=str(fixture), MD_GATE_CAPTURE=str(REPO / "tests/ui-captures-markdown.sh"))
    for view in ["rendered", "source"]:
        env["MD_GATE_COLUMN_VIEW"] = view
        result = subprocess.run(["/bin/bash", str(capture)], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=PROBE_TIMEOUT_SECONDS)
        if view == "source":
            check(result.returncode != 0 and "SHOT cap-markdown-column-after-flip" not in result.stdout
                  and "column-after-flip=ok" not in result.stdout,
                  "md3z F5 Source column refused before the after-flip capture")
        else:
            check(result.returncode == 0 and "SHOT cap-markdown-column-after-flip" in result.stdout
                  and "column-after-flip=ok" in result.stdout,
                  "md3z F5 Rendered column captured after IPC proof")

print(f"MARKDOWN_GATES {checks} checks, {failures} failed")
raise SystemExit(1 if failures else 0)
