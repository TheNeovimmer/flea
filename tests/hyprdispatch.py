#!/usr/bin/env python3
"""Reject unscoped window dispatches and discarded compositor replies."""
import json
import re
import subprocess
import sys
from pathlib import Path

WINDOW_CALL = re.compile(r"\bhl\.dsp\.(?:focus|window\.\w+)\s*\(")
SELECTOR = re.compile(r"\bwindow\s*=\s*[\"'](?:address|class|title):[^\"']+")
DISPATCH = re.compile(r"\bhyprctl\s+dispatch\b")
DISCARD = re.compile(r">\s*/dev/null\b")
FIXTURE_SCAN_TIMEOUT_SECONDS = 3
COMMAND_SEPARATORS = ("&&", "||", ";", "|", "\n")


# Sample input: addr=${addr#address:}; hyprctl dispatch 'hl.dsp.focus()' # checked
def shell_commands(text):
    chars, spans = list(text), []
    quote, escaped, comment = None, False, False
    word_start = True
    parameter_depth = 0
    start, index = 0, 0
    while index < len(text):
        char = text[index]
        if comment and char != "\n":
            chars[index] = " "
            index += 1
            continue
        comment = False
        if escaped:
            escaped = False
            if char != "\n":
                word_start = False
        elif char == "\\" and quote != "'":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
            word_start = False
        elif text.startswith("${", index):
            parameter_depth += 1
            word_start = False
        elif parameter_depth:
            if char == "}":
                parameter_depth -= 1
        elif char == "#" and word_start:
            chars[index] = " "
            comment = True
        else:
            separator = next((token for token in COMMAND_SEPARATORS if text.startswith(token, index)), None)
            if separator:
                spans.append((start, index))
                index += len(separator)
                start = index
                word_start = True
                continue
            word_start = char.isspace() or char in "(&"
        index += 1
    spans.append((start, len(text)))
    return "".join(chars), spans


# Sample input: echo address#part # hyprctl dispatch 'hl.dsp.focus()'
def without_comments(text):
    return shell_commands(text)[0]


# Sample input: focus({ window = "title:foo(bar)" })
def call_end(text, start):
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


# Sample input: hyprctl dispatch 'hl.dsp.focus({ window = "address:0xabc" })' >/dev/null
def scan(text):
    code, spans = shell_commands(text)
    issues, count = [], 0
    first_line, previous_start = 1, 0
    for start, stop in spans:
        first_line += code.count("\n", previous_start, start)
        previous_start = start
        command = code[start:stop].replace('\\"', '"').replace("\\'", "'")
        for match in WINDOW_CALL.finditer(command):
            count += 1
            end = call_end(command, match.end() - 1)
            line = first_line + command.count("\n", 0, match.start())
            if not SELECTOR.search(command[match.end():end]):
                issues.append((line, "hypr-window-selector"))
            dispatches = list(DISPATCH.finditer(command[:match.start()]))
            outside_call = command[dispatches[-1].end():match.start()] + command[end:] if dispatches else ""
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
        if fixture.get("bounded"):
            try:
                result = subprocess.run([sys.executable, __file__, "--scan-fixture"], input=fixture["code"],
                                        text=True, capture_output=True, check=True, timeout=FIXTURE_SCAN_TIMEOUT_SECONDS)
            except subprocess.TimeoutExpired:
                problems.append(f"fixture {fixture['name']}: scan exceeded {FIXTURE_SCAN_TIMEOUT_SECONDS}s bound")
                continue
            count, issues = json.loads(result.stdout)
        else:
            count, issues = scan(fixture["code"])
        if "calls" in fixture and count != fixture["calls"]:
            problems.append(f"fixture {fixture['name']}: expected {fixture['calls']} call(s), got {count}")
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
    if sys.argv[1:] == ["--scan-fixture"]:
        print(json.dumps(scan(sys.stdin.read())))
    else:
        sys.exit(main())
