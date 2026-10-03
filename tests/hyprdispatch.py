#!/usr/bin/env python3
"""Keep compositor command construction inside the typed helper."""
import json
import re
import sys
from pathlib import Path

LUA_PREFIX = "hl." + "dsp."
RAW_WORDS = ("dispatch", "--batch")
EXEMPT_FILES = (
    "tests/lib/hypr-dispatch.sh",  # The helper owns raw commands and still contributes its call count.
    "tests/hypr-dispatch-proof.py",  # The proof executes raw command fixtures against a fake compositor.
    "tests/hyprdispatch.py",  # The scanner contains the words and patterns that it refuses elsewhere.
)
SOURCE_SUFFIXES = (".sh", ".py", ".qml", ".js")
COMMENT_PREFIXES = ("#", "//")
FIRST_LINE = 1
SEPARATORS = r"[\s'\",\\\[\]()]"
DASH_FLAG = r"(?!--batch(?![\w-]))--?[\w-]+"
QUERY_WORDS = ("clients", "cursorpos", "activewindow", "monitors", "getoption", "activeworkspace", "binds", "configerrors")
RAW_REFUSAL_ADVICE = ": make the call a complete query, or reword the prose that names dispatch/--batch"

# Sample input: 'args=(dispatch x)' names a raw word, but 'dispatch_x --batch-size' does not.
RAW_WORD = re.compile(r"(?<![\w-])(?:dispatch|--batch)(?![\w-])")

# Sample input: 'command -v hyprctl' names the tool, but 'real_hyprctl' does not.
HYPRCTL_WORD = re.compile(r"(?<![\w-])hyprctl(?![\w-])")

# Sample input: 'run(["hyprctl", "-j", "clients"])' is a complete query on one physical line.
COMPLETE_QUERY = re.compile(
    rf"hyprctl{SEPARATORS}+"
    rf"(?:{DASH_FLAG}{SEPARATORS}+)*"
    rf"(?:{'|'.join(QUERY_WORDS)})(?![\w-])"
)

# Sample input: "hl.\\\ndsp.focus()" retains the split-prefix verdict without quote or bracket state.
CONTINUED_LUA_PREFIX = re.compile(r"(?:\\\r?\n)*".join(re.escape(character) for character in LUA_PREFIX))


# Sample input: hypr_window_focus "$addr" || fail nope
def scan(text, helper_file=False):
    issues = []
    count = 0
    raw_lines = set()
    lua_lines = set()
    comment_free_lines = ["" if line.lstrip().startswith(COMMENT_PREFIXES) else line for line in text.splitlines()]
    comment_free_text = "\n".join(comment_free_lines)
    has_raw_word = RAW_WORD.search(comment_free_text) is not None
    for number, line in enumerate(comment_free_lines, start=FIRST_LINE):
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
        # Rule B refuses each non-query tool mention in a file naming a whole raw word.
        if has_raw_word and number not in raw_lines:
            if any(COMPLETE_QUERY.match(line, match.start()) is None for match in HYPRCTL_WORD.finditer(line)):
                issues.append((number, "hypr-window-reply"))
                raw_lines.add(number)
    for match in CONTINUED_LUA_PREFIX.finditer(comment_free_text):
        if "\n" not in match.group():
            continue
        count += 1
        number = comment_free_text[:match.start()].count("\n") + FIRST_LINE
        if not helper_file and number not in lua_lines:
            issues.append((number, "hypr-window-selector"))
            lua_lines.add(number)
    return count, sorted(issues, key=lambda issue: issue[0])


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    fixtures = json.loads(Path(__file__).with_name("fixtures").joinpath("hypr-dispatch.json").read_text())
    problems = []
    calls = 0
    files = sorted(path for path in (root / "tests").rglob("*") if path.suffix in SOURCE_SUFFIXES)
    for path in files:
        relative = path.relative_to(root).as_posix()
        count, issues = scan(path.read_text(), helper_file=relative in EXEMPT_FILES)
        calls += count
        problems.extend(f"{relative}:{line}: {rule}" + (RAW_REFUSAL_ADVICE if rule == "hypr-window-reply" else "")
                        for line, rule in issues)
    for fixture in fixtures:
        count, issues = scan(fixture["code"], helper_file=fixture.get("helper_file", False))
        if count != fixture["calls"]:
            problems.append(f"fixture {fixture['name']}: expected {fixture['calls']} call(s), got {count}")
        actual = [rule for _, rule in issues]
        if actual != fixture["issues"]:
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
