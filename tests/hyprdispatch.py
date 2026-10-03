#!/usr/bin/env python3
"""Keep compositor command construction inside the typed helper."""
import json
import re
import sys
from pathlib import Path

LUA_PREFIX = "hl." + "dsp."
RAW_WORDS = ("dispatch", "--batch")
HELPER_FILE = "tests/lib/hypr-dispatch.sh"
SOURCE_SUFFIXES = (".sh", ".py", ".qml", ".js")
COMMENT_PREFIXES = ("#", "//")
FIRST_LINE = 1
SEPARATORS = r"[\s'\",\\\[\]()]"
DASH_FLAG = r"--?[\w-]+"
TRAILING_COMMENT = r"[^\S\r\n]+(?:#|//).*"

# Sample input: 'run(["hyprctl",\n"-j", "dispatch"])' is refused by rule B at the hyprctl line.
RAW_CALL = re.compile(
    rf"(?<![\w-])hyprctl{SEPARATORS}+"
    rf"(?:{DASH_FLAG}{SEPARATORS}+)*"
    r"(?:dispatch|--batch)(?![\w-])"
)

# Sample input: "hl.\\\ndsp.focus()" retains the split-prefix verdict without quote or bracket state.
CONTINUED_LUA_PREFIX = re.compile(r"(?:\\\r?\n)*".join(re.escape(character) for character in LUA_PREFIX))


# Sample input: hypr_window_focus "$addr" || fail nope
def scan(text, helper_file=False):
    issues = []
    count = 0
    raw_lines = set()
    lua_lines = set()
    comment_free_lines = []
    for number, line in enumerate(text.splitlines(), start=FIRST_LINE):
        if line.lstrip().startswith(COMMENT_PREFIXES):
            comment_free_lines.append("")
            continue
        comment_free_lines.append(line)
        count += line.count(LUA_PREFIX)
        if helper_file:
            continue
        if LUA_PREFIX in line:
            issues.append((number, "hypr-window-selector"))
            lua_lines.add(number)
        # Rule A deliberately refuses any non-comment physical line containing both command words.
        if "hyprctl" in line and any(word in line for word in RAW_WORDS):
            issues.append((number, "hypr-window-reply"))
            raw_lines.add(number)
    comment_free_text = "\n".join(comment_free_lines)
    for match in CONTINUED_LUA_PREFIX.finditer(comment_free_text):
        if "\n" not in match.group():
            continue
        count += 1
        number = comment_free_text[:match.start()].count("\n") + FIRST_LINE
        if not helper_file and number not in lua_lines:
            issues.append((number, "hypr-window-selector"))
            lua_lines.add(number)
    if not helper_file:
        raw_text = re.sub(TRAILING_COMMENT, "", comment_free_text, flags=re.MULTILINE)
        for match in RAW_CALL.finditer(raw_text):
            number = raw_text[:match.start()].count("\n") + FIRST_LINE
            if number not in raw_lines:
                issues.append((number, "hypr-window-reply"))
                raw_lines.add(number)
    return count, sorted(issues, key=lambda issue: issue[0])


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
        # Issue order is not part of the refusal contract.
        if sorted(actual) != sorted(fixture["issues"]):
            problems.append(f"fixture {fixture['name']}: expected {fixture['issues']}, got {actual}")
        if "issue_lines" in fixture:
            actual_lines = [line for line, _ in issues]
            if actual_lines != fixture["issue_lines"]:
                problems.append(f"fixture {fixture['name']}: expected lines {fixture['issue_lines']}, got {actual_lines}")
    if not files or not calls or not fixtures:
        problems.append("empty source or fixture sweep")
    for problem in problems:
        print("FAIL " + problem)
    print(f"hypr-window-dispatch: {len(files)} file(s), {calls} call(s), {len(problems)} problem(s)")
    return bool(problems)


if __name__ == "__main__":
    sys.exit(main())
