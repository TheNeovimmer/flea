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
current_row=""
goto_row() { current_row="$1"; }
row_index_of() { echo "$1"; }
settle() { :; }
shot() { printf 'SHOT %s\\n' "$1"; }
switch_view() { :; }
kill_flea() { :; }
window_box() { echo '0 0 800 600'; }
# Sample input: omarchy-drive move 714 50 puts the pointer on the 24 px close button at MD_GATE_CLOSE_X, whatever centre the reader reports.
hit=false
held=false
focused=false
scroll_y=0
scroll_max=5760
# The capture scrolls 15 notches of 288 px, 4320, and the stub builds the last block from here on.
end_reach=4000
close_reach=12
bar_reach=10
omarchy-drive() {
    case "$1" in
        move)
            hit=false
            if [ "$2" -ge $((MD_GATE_CLOSE_X - close_reach)) ] && [ "$2" -le $((MD_GATE_CLOSE_X + close_reach)) ] \
                    && [ "$3" -ge $((50 - bar_reach)) ] && [ "$3" -le $((50 + bar_reach)) ]; then hit=true; fi ;;
        scroll)
            [ -z "${MD_GATE_SCROLL_FAIL:-}" ] || return 1
            [ -z "${MD_GATE_NO_SCROLL:-}" ] || return 0
            if [ "$2" = down ]; then scroll_y=$((scroll_y + $3 * 288)); else scroll_y=$((scroll_y - $3 * 288)); fi
            [ "$scroll_y" -ge 0 ] || scroll_y=0
            [ "$scroll_y" -le "$scroll_max" ] || scroll_y=$scroll_max ;;
    esac
}
# Sample input: ydotool click 0x40 presses the left button, 0x80 releases it, 0xC0 does both.
ydotool() {
    case "$2" in
        0x40) if $hit && [ -z "${MD_GATE_PRESS_DEAD:-}" ]; then held=true; fi ;;
        0x80) if $held && $hit && [ -z "${MD_GATE_CLOSE_DEAD:-}" ]; then opened=false; fi; held=false ;;
        0xC0) if $hit && [ -z "${MD_GATE_CLOSE_DEAD:-}" ]; then opened=false; fi ;;
    esac
}
XDG_RUNTIME_DIR=$MD_GATE_FIXTURE
seq() { echo 1; }
sleep() { :; }
fail() {
    printf 'REFUSED %s\\n' "$*"
    exit 1
}
key() {
    case "$*" in
        "-k Tab") [ -n "${MD_GATE_TAB_DEAD:-}" ] || { if $focused; then focused=false; else focused=true; fi; } ;;
        "-k Space") opened=true; scroll_y=0 ;;
        "-k Escape") opened=false ;;
    esac
}
ipc() {
    case "$1" in
        previewOpen) echo "$opened" ;;
        previewFigures) echo "${MD_GATE_FIGURES:-1=ready,2=ready,3=ready,4=ready,5=failed}" ;;
        previewMarkdownView) echo "${MD_GATE_PREVIEW_VIEW:-rendered}" ;;
        columnMarkdownView) echo "$MD_GATE_COLUMN_VIEW" ;;
        previewSurfaceRect) echo '40 40 700 500' ;;
        chromeHeight) echo 20 ;;
        previewCloseState) if [ -n "${MD_GATE_NO_CENTRE:-}" ]; then printf '{"hovered":%s,"pressed":%s,"focused":%s}\\n' "$hit" "$held" "$focused"; else printf '{"hovered":%s,"pressed":%s,"focused":%s,"centre":"%s 50"}\\n' "$hit" "$held" "${MD_GATE_FOCUS_STUCK:-$focused}" "${MD_GATE_CENTRE_X:-$MD_GATE_CLOSE_X}"; fi ;;
        previewEndGap) if [[ " ${MD_GATE_FIT:-} " == *" $current_row "* ]]; then echo 0; elif [ "$scroll_y" -ge "$end_reach" ]; then echo "${MD_GATE_END_CUT:-0}"; else echo -1; fi ;;
        previewScrollY) echo "$scroll_y" ;;
    esac
}
. "$MD_GATE_CAPTURE"
# The stub answers at once, so a refused hover or press needs only one second of its deadline.
capmarkdown_close_wait_s=1
${MD_GATE_CASE:-case_cap_markdown}
''')
    env = dict(os.environ, MD_GATE_FIXTURE=str(fixture), MD_GATE_CAPTURE=str(REPO / "tests/ui-captures-markdown.sh"),
               MD_GATE_CLOSE_X="714")
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

    # The close-button and scroll steps each refuse on the evidence they lack, and the faithful stub passes them all.
    env["MD_GATE_COLUMN_VIEW"] = "rendered"

    def refusal(extra, text, label):
        result = subprocess.run(["/bin/bash", str(capture)], env=dict(env, **extra), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=PROBE_TIMEOUT_SECONDS)
        check(result.returncode != 0 and ("REFUSED " + text) in result.stdout and "CAPMARKDOWN quicklook=ok" not in result.stdout, label)

    refusal({"MD_GATE_CENTRE_X": "600"}, "capmarkdown: the close button never reported hovered=true", "mdfid B2 a pointer that misses the close button is refused")
    refusal({"MD_GATE_NO_CENTRE": "1"}, "capmarkdown: the close button never reported its centre", "mdfid B2 a close button with no centre is refused")
    refusal({"MD_GATE_PRESS_DEAD": "1"}, "capmarkdown: the close button never reported pressed=true", "mdfid B2 a press the close button never takes is refused")
    refusal({"MD_GATE_CLOSE_DEAD": "1"}, "capmarkdown: a press and release on the close button did not close Quick Look", "mdfid B2 a close button that never closes is refused")
    refusal({"MD_GATE_NO_SCROLL": "1"}, "capmarkdown: the wheel did not move the view", "mdfid B4 a scroll that moves nothing is refused")
    refusal({"MD_GATE_SCROLL_FAIL": "1"}, "capmarkdown: scroll down", "mdfid B4 a failed scroll call is refused")
    refusal({"MD_GATE_END_CUT": "80"}, "capmarkdown: the last block is cut at the end of the document", "mdfid N1 a picture that grew below the end is refused")
    refusal({"MD_GATE_TAB_DEAD": "1"}, "capmarkdown: the close button never reported focused=true", "mdfid N2 a Tab that never reaches the close mark is refused")
    refusal({"MD_GATE_FOCUS_STUCK": "true"}, "capmarkdown: the close button never reported focused=false", "mdfid N2 a close mark focused at rest is refused")

    # The kinds case shoots five documents and the nested column, each shot waiting on its own proof; tables.md standing for the one that fits the card.
    kinds = ["tables", "readme", "badges", "nesting", "figures"]

    def kinds_run(extra):
        return subprocess.run(["/bin/bash", str(capture)], env=dict(env, MD_GATE_CASE="case_cap_markdown_kinds", **extra), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=PROBE_TIMEOUT_SECONDS)

    def kinds_refusal(extra, text, label):
        result = kinds_run(extra)
        check(result.returncode != 0 and ("REFUSED " + text) in result.stdout and "CAPMARKDOWNKINDS" not in result.stdout, label)

    result = kinds_run({"MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=failed"})
    shots = [line.split()[1] for line in result.stdout.splitlines() if line.startswith("SHOT ")]
    want = ["cap-markdown-kind-%s%s" % (name, tail) for name in kinds for tail in ("", "-end")] + ["cap-markdown-kind-column-nesting"]
    check(result.returncode == 0 and shots == want
          and "CAPMARKDOWNKINDS tables=ok readme=ok badges=ok nesting=ok figures=ok column-nesting=ok" in result.stdout,
          "capmd the kinds case shoots each document, its end and the nested column in order")
    result = kinds_run({"MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=failed", "MD_GATE_FIT": "tables.md"})
    shots = [line.split()[1] for line in result.stdout.splitlines() if line.startswith("SHOT ")]
    check(result.returncode == 0 and "cap-markdown-kind-tables" in shots and "cap-markdown-kind-tables-end" not in shots
          and "cap-markdown-kind-readme-end" in shots, "capmd a document that fits the card gets no end shot")
    listing = sorted(path.name for path in (fixture / "capmarkdownkinds" / "listing").iterdir())
    check(listing == ["badges.md", "bands.png", "figures.md", "logo.png", "nesting.md", "readme.md", "tables.md"], "capmd the kinds fixture holds the seven files")
    nesting = (fixture / "capmarkdownkinds" / "listing" / "nesting.md").read_text()
    check(nesting.endswith("\n&#49;. ol\n\n- an item with a picture\n\n  ![bands](logo.png)\n\n> a quote with a picture\n>\n> ![bands](logo.png)\n\nAfter the pictures.\n")
          and "Inline maths $x^2 + y^2$ in a line." in nesting, "capmd nesting.md is the board text with the picture-in-block tail")
    check("| Left | Centre | Right |" in (fixture / "capmarkdownkinds" / "listing" / "tables.md").read_text()
          and (fixture / "capmarkdownkinds" / "listing" / "badges.md").read_text().count("<img") == 16
          and '<div align="right">' in (fixture / "capmarkdownkinds" / "listing" / "readme.md").read_text(), "capmd tables, badges and readme carry their board text")
    kinds_refusal({"MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=ready,5=failed"}, "capmarkdownkinds: want 3 ready figures", "capmd a figures document with four ready is refused")
    kinds_refusal({"MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=ready"}, "capmarkdownkinds: want 3 ready figures", "capmd a figures document with no failed figure is refused")
    kinds_refusal({"MD_GATE_PREVIEW_VIEW": "source"}, "capmarkdownkinds: tables.md never rendered", "capmd a Quick Look that never renders is refused")
    kinds_refusal({"MD_GATE_END_CUT": "80", "MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=failed"}, "capmarkdown: the last block is cut at the end of the document", "capmd a picture that grew below the end is refused")
    env["MD_GATE_COLUMN_VIEW"] = "source"
    kinds_refusal({"MD_GATE_FIGURES": "1=ready,2=ready,3=ready,4=failed"}, "capmarkdown: column Markdown never rendered", "capmd a Source column is refused before the nesting shot")

print(f"MARKDOWN_GATES {checks} checks, {failures} failed")
raise SystemExit(1 if failures else 0)
