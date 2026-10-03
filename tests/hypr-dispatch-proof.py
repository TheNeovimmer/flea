#!/usr/bin/env python3
"""Run the real harness helpers against a shell fake, without a compositor."""
import ast
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

WARNING = "warning: =[C]:-1: hl.focus: window not found"
PARSER_SAMPLE_PREFIX = "# Sample input: "
FAKE = r'''#!/usr/bin/env bash
set -u
case "$1" in
    clients) printf '%s\n' "$HYPR_FAKE_CLIENTS" ;;
    activewindow) cat "$HYPR_FAKE_ACTIVE" ;;
    dispatch)
        printf '%s\n' "$2" >> "$HYPR_FAKE_LOG"
        if [[ "$2" != *address:* || ( -n "${HYPR_FAKE_FAIL_ACTION:-}" && "$2" == *"$HYPR_FAKE_FAIL_ACTION"* ) ]]; then
            printf '%s\n' 'warning: =[C]:-1: hl.focus: window not found'
        else
            if [[ "$2" == *hl.dsp.focus* ]]; then
                printf '%s\n' '{"pid":111}' > "$HYPR_FAKE_ACTIVE"
            fi
            printf '%s\n' "${HYPR_FAKE_REPLY-ok}"
        fi
        exit "${HYPR_FAKE_STATUS:-0}"
        ;;
    *) printf 'fake hyprctl refused unexpected command: %s\n' "$*" >&2; exit 2 ;;
esac
'''


# Sample input: "hypr_dispatch() {\n    echo ok\n}" with names=["hypr_dispatch"].
def functions(text, names):
    # Keep all definitions in source order so the baseline's later duplicate really wins.
    pattern = r"(?ms)^(?:" + "|".join(names) + r")\(\) \{\n.*?^\}"
    return "\n".join(match.group() for match in re.finditer(pattern, text))


def main():
    root = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "tests/ui.sh"
    text = source.read_text()
    helpers = functions(text, ["hypr_dispatch", "fail", "xwdrag_addr", "xwdrag_focus", "xwdrag_assert_focus", "xwdrag_place"])
    drag_helper = functions((root / "tests/drag.sh").read_text(), ["hypr_dispatch"])
    failures, checks = [], 0
    with tempfile.TemporaryDirectory(prefix="hypr-proof-", dir=os.environ.get("TMPDIR")) as directory:
        scratch = Path(directory)
        fake = scratch / "hyprctl"
        fake.write_text(FAKE)
        fake.chmod(0o755)
        environment = dict(os.environ, PATH=str(scratch) + os.pathsep + os.environ["PATH"])
        environment.update(HYPR_FAKE_LOG=str(scratch / "dispatch.log"), HYPR_FAKE_ACTIVE=str(scratch / "active.json"))
        environment["HYPR_FAKE_CLIENTS"] = '[{"pid":111,"address":"0xabc"}]'
        for name in ("HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY"):
            environment.pop(name, None)

        def run(command, code=helpers, **overrides):
            (scratch / "dispatch.log").write_text("")
            (scratch / "active.json").write_text('{"pid":999}\n')
            script = "set -uo pipefail\n" + code + "\nsleep() { :; }\n" + command
            result = subprocess.run(["bash", "-c", script], env=dict(environment, **overrides), text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
            calls = (scratch / "dispatch.log").read_text().splitlines()
            return result.returncode, result.stdout, calls

        def check(name, holds, output=""):
            nonlocal checks
            checks += 1
            if not holds:
                failures.append(name)
                print(f"FAIL hypr-dispatch-proof {name}: {output.strip()}")

        for relative, names in (("tests/hyprdispatch.py", ("without_comments", "scan")),
                                ("tests/hypr-dispatch-proof.py", ("functions",))):
            parser_source = (root / relative).read_text()
            source_lines = parser_source.splitlines()
            definitions = {node.name: node for node in ast.walk(ast.parse(parser_source))
                           if isinstance(node, ast.FunctionDef)}
            for name in names:
                definition = definitions.get(name)
                documented = definition is not None and definition.lineno > 1
                if documented:
                    documented = source_lines[definition.lineno - 2].strip().startswith(PARSER_SAMPLE_PREFIX)
                check("sample input directly above " + name, documented, relative)

        rc, output, calls = run("xwdrag_focus 111")
        check("addressed focus reaches the wanted PID", rc == 0 and len(calls) == 1 and "address:0xabc" in calls[0], output)
        rc, output, calls = run("xwdrag_place 111 40 80 1000 720")
        actions = [re.search(r"hl\.dsp\.(focus|window\.\w+)", call).group(1) for call in calls]
        check("addressed placement keeps float, resize, move order", rc == 0 and actions == ["focus", "window.float", "window.resize", "window.move"], output)
        check("every placement call names the owned window", len(calls) == 4 and all('window = "address:0xabc"' in call for call in calls), "\n".join(calls))
        check("floating is on and resize is exact", len(calls) == 4 and 'action = "on"' in calls[1] and "exact = true" in calls[2], "\n".join(calls))

        bare_helpers = helpers.replace("address:$addr", "$addr")
        for helper, arguments in (("xwdrag_focus", "111"), ("xwdrag_place", "111 40 80 1000 720")):
            rc, output, calls = run(f"{helper} {arguments}", code=bare_helpers)
            check(helper + " rejects a bare selector immediately with its answer", rc == 1 and WARNING in output and "could not focus 111" in output and len(calls) == 1, output)
            print(f"{helper} bare control: exit={rc}, dispatches={len(calls)}, answer={output.strip()!r}")

        for index, action in enumerate(("window.float", "window.resize", "window.move"), start=2):
            rc, output, calls = run("xwdrag_place 111 40 80 1000 720", HYPR_FAKE_FAIL_ACTION=action)
            check(action + " stops placement on an exit-zero warning", rc == 1 and WARNING in output and len(calls) == index, output)

        for name, clients in (("missing", "[]"), ("ambiguous", '[{"pid":111,"address":"0xabc"},{"pid":111,"address":"0xdef"}]'), ("malformed", "not json")):
            rc, output, _ = run("xwdrag_addr 111", HYPR_FAKE_CLIENTS=clients)
            check(name + " address lookup fails loud", rc != 0 and "xwdrag: no " in output, output)

        expression = 'hl.dsp.focus({ window = "address:0xabc" })'
        for owner, code in (("ui", helpers), ("drag", drag_helper)):
            command = "hypr_dispatch " + shlex.quote(expression)
            rc, output, _ = run(command, code=code)
            check(owner + " accepts exactly ok", rc == 0 and not output, output)
            for reply in (WARNING, "", "ok\nwarning", " ok", "okay"):
                rc, output, _ = run(command, code=code, HYPR_FAKE_REPLY=reply)
                check(owner + " rejects reply " + repr(reply), rc == 1 and output == reply + "\n", output)
            rc, output, _ = run(command, code=code, HYPR_FAKE_STATUS="7")
            check(owner + " rejects a nonzero command even with ok", rc == 1 and output == "ok\n", output)

    print(f"hypr-dispatch-proof: {checks - len(failures)} passed, {len(failures)} failed")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
