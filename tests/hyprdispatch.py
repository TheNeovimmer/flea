#!/usr/bin/env python3
"""Reject unscoped window dispatches and discarded compositor replies."""
import json
import re
import sys
from pathlib import Path

WINDOW_CALL = re.compile(r"\bhl\.dsp\.(?:focus|window\.\w+)\s*\(")
SELECTOR = re.compile(r"\bwindow\s*=\s*[\"'](?:address|class|title):[^\"']+")
DISPATCH = re.compile(r"\bhyprctl\s+dispatch\b")
DISCARD = re.compile(r">\s*/dev/null\b")


def without_comments(text):
    # Keep newlines and offsets intact, including hashes inside quoted selectors.
    chars, quote, escaped, comment = list(text), None, False, False
    for index, char in enumerate(text):
        if comment:
            if char == "\n":
                comment = False
            else:
                chars[index] = " "
        elif escaped:
            escaped = False
        elif char == "\\" and quote != "'":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "#":
            chars[index], comment = " ", True
    return "".join(chars)


def call_end(text, start):
    # Sample input: focus({ window = "title:foo(bar)" }) closes after the table.
    depth, quote, escaped = 0, None, False
    for index in range(start, len(text)):
        char = text[index]
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(text)


def scan(text):
    code = without_comments(text).replace('\\"', '"').replace("\\'", "'")
    issues, count = [], 0
    for match in WINDOW_CALL.finditer(code):
        count += 1
        end = call_end(code, match.end() - 1)
        line = code.count("\n", 0, match.start()) + 1
        if not SELECTOR.search(code[match.end():end]):
            issues.append((line, "hypr-window-selector"))
        start = code.rfind("\n", 0, match.start()) + 1
        while start > 0 and code[:start - 1].rstrip(" \t").endswith("\\"):
            start = code.rfind("\n", 0, start - 1) + 1
        stop = code.find("\n", end)
        if stop < 0:
            stop = len(code)
        while code[end:stop].rstrip(" \t").endswith("\\"):
            following = code.find("\n", stop + 1)
            stop = len(code) if following < 0 else following
        dispatches = list(DISPATCH.finditer(code[start:match.start()]))
        outside_call = code[start + dispatches[-1].end():match.start()] + code[end:stop] if dispatches else ""
        if dispatches and DISCARD.search(outside_call):
            issues.append((line, "hypr-window-reply"))
    return count, issues


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    fixtures = json.loads(Path(__file__).with_name("fixtures").joinpath("hypr-dispatch.json").read_text())
    problems, calls = [], 0
    files = sorted(path for path in (root / "tests").rglob("*") if path.suffix in (".sh", ".py"))
    for path in files:
        count, issues = scan(path.read_text())
        calls += count
        problems.extend(f"{path.relative_to(root)}:{line}: {rule}" for line, rule in issues)
    for fixture in fixtures:
        _, issues = scan(fixture["code"])
        actual = [rule for _, rule in issues]
        if actual != fixture["issues"]:
            problems.append(f"fixture {fixture['name']}: expected {fixture['issues']}, got {actual}")
    if not files or not calls or not fixtures:
        problems.append("empty source or fixture sweep")
    for problem in problems:
        print("FAIL " + problem)
    print(f"hypr-window-dispatch: {len(files)} file(s), {calls} call(s), {len(problems)} problem(s), {len(fixtures)} fixture(s) held")
    return bool(problems)


if __name__ == "__main__":
    sys.exit(main())
