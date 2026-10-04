#!/usr/bin/env python3
"""The Markdown spec examples as files for the capture suite: <work>/md/<n>.md for each, and <work>/md/manifest.json listing them in order.

Usage: mdspec-manifest.py WORK [LIMIT]; an entry holds markdown, html, section, example, n, group (its contact-sheet group) and state (pass, or its rule).
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "markdown-spec")
# The cmark spec fences each example in this many backticks.
EXAMPLE_FENCE_TICKS = 32
# The hand-written fixtures, each with the prefix its example ids carry in tests/markdown-spec.qml.
HAND_FORMS = [("gfm-table-forms.json", "table-"), ("entity-forms.json", "entity-forms-"), ("definition-forms.json", "definition-forms-")]
# The sheets, each the spec sections it gathers; a section not named lands on "other".
GROUPS = [
    ("tables", ["GFM table", "GFM table forms"]),
    ("lists", ["List items", "Lists", "GFM task list items"]),
    ("block-quotes", ["Block quotes"]),
    ("emphasis", ["Emphasis and strong emphasis", "GFM strikethrough"]),
    ("links", ["Links", "Link reference definitions", "Autolinks", "GFM autolink", "Definition forms"]),
    ("images", ["Images"]),
    ("code", ["Code spans", "Fenced code blocks", "Indented code blocks"]),
    ("html", ["HTML blocks", "Raw HTML", "GFM tagfilter"]),
    ("entities", ["Entity and numeric character references", "Backslash escapes", "Entity forms"]),
    ("headings", ["ATX headings", "Setext headings"]),
    ("breaks", ["Hard line breaks", "Soft line breaks", "Thematic breaks"]),
]
OTHER_GROUP = "other"


def read(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as handle:
        return handle.read()


# Sample input: a 32-tick fence "example table", Markdown, a "." line, HTML and a closing fence answers one example; the arrow is a tab.
def gfm_examples(text):
    lines = text.split("\n")
    ticks = "`" * EXAMPLE_FENCE_TICKS
    fence = ticks + " example"
    out = []
    section = ""
    number = 0
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith(fence):
            heading = re.match(r"^## (.*)$", line)
            if heading:
                section = heading.group(1)
            i += 1
            continue
        kind = line[len(fence):].strip()
        md, markup = [], []
        target = md
        i += 1
        while i < len(lines) and not lines[i].startswith(ticks):
            if lines[i] == ".":
                target = markup
            else:
                target.append(lines[i])
            i += 1
        i += 1
        number += 1
        if kind == "":
            continue
        out.append({"markdown": "\n".join(md).replace("→", "\t") + "\n",
                    "html": "\n".join(markup).replace("→", "\t") + ("\n" if markup else ""),
                    "section": "GFM task list items" if kind == "disabled" else "GFM " + kind,
                    "example": "gfm%d" % number})
    return out


# Sample input: `ids: ["1", "2"]` under a rule named "link-gate" maps ids 1 and 2 to that rule.
def rule_of():
    with open(os.path.join(ROOT, "tests", "mdspec-rules.js"), encoding="utf-8") as handle:
        source = handle.read()
    rules = {}
    for name, ids in re.findall(r'"([a-z-]+)": \{\s*text: .*?\s*ids: \[(.*?)\]', source, re.S):
        for example in re.findall(r'"([^"]+)"', ids):
            rules[example] = name
    return rules


def examples():
    out = []
    for item in json.loads(read("commonmark-0.31.2-spec.json")):
        out.append({"markdown": item["markdown"], "html": item["html"], "section": item["section"], "example": str(item["example"])})
    out.extend(gfm_examples(read("gfm-spec.txt")))
    for name, prefix in HAND_FORMS:
        for item in json.loads(read(name)):
            out.append({"markdown": item["markdown"], "html": item["html"], "section": item["section"], "example": prefix + item["example"]})
    return out


def group_of(section):
    for name, sections in GROUPS:
        if section in sections:
            return name
    return OTHER_GROUP


def manifest(work, limit):
    rules = rule_of()
    md_dir = os.path.join(work, "md")
    os.makedirs(md_dir, exist_ok=True)
    listed = []
    every = examples()
    for n, item in enumerate(every[:limit] if limit > 0 else every):
        with open(os.path.join(md_dir, "%d.md" % n), "w", encoding="utf-8") as handle:
            handle.write(item["markdown"])
        item["n"] = n
        item["group"] = group_of(item["section"])
        item["state"] = rules.get(item["example"], "pass")
        listed.append(item)
    with open(os.path.join(md_dir, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(listed, handle)
    print("manifest %d examples" % len(listed))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: mdspec-manifest.py WORK [LIMIT]")
    manifest(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 0)
