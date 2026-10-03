#!/usr/bin/env python3
"""Require the checked compositor helper and explicit selectors, one line at a time."""
import json
import re
import sys
from pathlib import Path

# Sample input: 'hl[.]dsp[.](focus[(]|window[.])\n(^|[,{])\s*window\s*=\s*"(address|class|title):\n'
WINDOW_CALL, WINDOW_SELECTOR = (re.compile(pattern) for pattern in
                                (Path(__file__).parent / "lib/hypr-dispatch.regex").read_text().splitlines())
RAW_DISPATCH = re.compile(r"\bhyprctl\s+(?:-\S+\s+(?:\S+\s+)*?)?(?:dispatch|--batch)\b")
HELPER_FILE = "tests/lib/hypr-dispatch.sh"
SOURCE_SUFFIXES = (".sh", ".py", ".qml")


# Sample input: hypr_dispatch 'hl.dsp.focus({ window = "address:0xabc" })' || fail nope
def scan(text, helper_file=False):
    issues, count = [], 0
    in_helper = False
    # Window dispatches and their address:, class: or title: selector must share one line.
    for number, line in enumerate(text.splitlines(), start=1):
        if line.lstrip().startswith("#"):
            continue
        if helper_file and line == "hypr_dispatch() {":
            in_helper = True
        if not in_helper and RAW_DISPATCH.search(line):
            issues.append((number, "hypr-window-reply"))
        matches = len(WINDOW_CALL.findall(line))
        count += matches
        if matches and not WINDOW_SELECTOR.search(line.replace('\\"', '"')):
            issues.append((number, "hypr-window-selector"))
        if line == "}":
            in_helper = False
    return count, issues


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    fixtures = json.loads(Path(__file__).with_name("fixtures").joinpath("hypr-dispatch.json").read_text())
    problems, calls = [], 0
    files = sorted(path for path in (root / "tests").rglob("*") if path.suffix in SOURCE_SUFFIXES)
    for path in files:
        relative = path.relative_to(root).as_posix()
        count, issues = scan(path.read_text(), helper_file=relative == HELPER_FILE)
        calls += count
        problems.extend(f"{relative}:{line}: {rule}" for line, rule in issues)
    for fixture in fixtures:
        count, issues = scan(fixture["code"], helper_file=fixture.get("helper_file", False))
        if "calls" in fixture and count != fixture["calls"]:
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
    if sys.argv[1:] == ["--scan-fixture"]:
        print(json.dumps(scan(sys.stdin.read())))
    else:
        sys.exit(main())
