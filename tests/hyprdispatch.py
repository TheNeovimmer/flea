#!/usr/bin/env python3
"""Keep compositor command construction inside the typed helper."""
import json
import sys
from pathlib import Path

LUA_PREFIX = "hl." + "dsp."
RAW_WORDS = ("dispatch", "--batch")
HELPER_FILE = "tests/lib/hypr-dispatch.sh"
SOURCE_SUFFIXES = (".sh", ".py", ".qml", ".js")


# Sample input: "hyprctl \\\ndispatch anything" yields one logical line starting at physical line 1.
def logical_lines(text):
    pending = ""
    first_line = 1
    for number, physical_line in enumerate(text.splitlines(keepends=True), start=1):
        line = physical_line.rstrip("\r\n")
        if physical_line.endswith(("\\\n", "\\\r\n")):
            pending += line.removesuffix("\\")
            continue
        yield first_line, pending + line
        pending = ""
        first_line = number + 1
    if pending:
        yield first_line, pending


# Sample input: hypr_window_focus "$addr" || fail nope
def scan(text, helper_file=False):
    issues = []
    count = 0
    for number, line in logical_lines(text):
        if line.lstrip().startswith(("#", "//")):
            continue
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
