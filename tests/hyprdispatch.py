#!/usr/bin/env python3
"""Keep compositor command construction inside the typed helper."""
import json
import sys
from pathlib import Path

LUA_PREFIX = "hl." + "dsp."
RAW_WORDS = ("dispatch", "--batch")
HELPER_FILE = "tests/lib/hypr-dispatch.sh"
SOURCE_SUFFIXES = (".sh", ".py", ".qml", ".js")
COMMENT_PREFIXES = ("#", "//")
OPEN_BRACKETS = "(["
CLOSE_BRACKETS = ")]"
QUOTE_MARKS = "'\""


# Sample input: 'run(["hyprctl",\n"dispatch"])' yields one logical line starting at physical line 1.
def logical_lines(text):
    pending = ""
    first_line = 1
    depth = 0
    quote = ""
    for number, physical_line in enumerate(text.splitlines(keepends=True), start=1):
        line = physical_line.rstrip("\r\n")
        if line.lstrip().startswith(COMMENT_PREFIXES):
            if pending and not depth:
                yield first_line, pending
                pending = ""
            if not pending:
                first_line = number + 1
            continue
        continued = physical_line.endswith(("\\\n", "\\\r\n"))
        if continued:
            line = line.removesuffix("\\")
        escaped = False
        for character in line:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif quote:
                if character == quote:
                    quote = ""
            elif character in QUOTE_MARKS:
                quote = character
            elif character in OPEN_BRACKETS:
                depth += 1
            elif character in CLOSE_BRACKETS and depth:
                depth -= 1
        pending += line
        if continued:
            continue
        if depth:
            pending += " "
            continue
        yield first_line, pending
        pending = ""
        first_line = number + 1
    if pending:
        yield first_line, pending


# Sample input: hypr_window_focus "$addr" || fail nope
def scan(text, helper_file=False):
    issues = []
    count = 0
    for number, line in logical_lines(text):
        count += line.count(LUA_PREFIX)
        if helper_file:
            continue
        if LUA_PREFIX in line:
            issues.append((number, "hypr-window-selector"))
        # Deliberately conservative: reword any refused line that is not a compositor command.
        if "hyprctl" in line and any(word in line for word in RAW_WORDS):
            issues.append((number, "hypr-window-reply"))
    return count, issues


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    fixtures = json.loads(Path(__file__).with_name("fixtures").joinpath("hypr-dispatch.json").read_text())
    problems = []
    calls = 0
    files = sorted(path for path in (root / "tests").rglob("*") if path.suffix in SOURCE_SUFFIXES)
    for path in files:
        relative = path.relative_to(root).as_posix()
        count, issues = scan(path.read_text(), helper_file=relative == HELPER_FILE)
        calls += count
        problems.extend(f"{relative}:{line}: {rule}" for line, rule in issues)
    for fixture in fixtures:
        count, issues = scan(fixture["code"], helper_file=fixture.get("helper_file", False))
        if count != fixture["calls"]:
            problems.append(f"fixture {fixture['name']}: expected {fixture['calls']} call(s), got {count}")
        actual = [rule for _, rule in issues]
        if actual != fixture["issues"]:
            problems.append(f"fixture {fixture['name']}: expected {fixture['issues']}, got {actual}")
    if not files or not calls or not fixtures:
        problems.append("empty source or fixture sweep")
    for problem in problems:
        print("FAIL " + problem)
    print(f"hypr-window-dispatch: {len(files)} file(s), {calls} call(s), {len(problems)} problem(s)")
    return bool(problems)


if __name__ == "__main__":
    sys.exit(main())
