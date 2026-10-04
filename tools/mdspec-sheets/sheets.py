#!/usr/bin/env python3
"""Contact sheets for the Markdown spec run: Flea's drawing beside the spec's own HTML, one PNG per section group."""
import html
import json
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FIXTURES = os.path.join(ROOT, "tests", "fixtures", "markdown-spec")
# The cmark spec fences each example in this many backticks.
EXAMPLE_FENCE_TICKS = 32
# The spec side is drawn at the width Flea's preview is, so line breaks fall alike.
SPEC_WIDTH = 480
COLUMNS = 2
# Chromium cannot screenshot past this many device pixels.
MAX_PAGE_HEIGHT = 16000
CHROMIUM = "/usr/bin/chromium"

# The sheets, each the spec sections it gathers; a section not named lands on "other".
GROUPS = [
    ("tables", ["GFM table", "GFM table forms"]),
    ("lists", ["List items", "Lists", "GFM task list items"]),
    ("block-quotes", ["Block quotes"]),
    ("emphasis", ["Emphasis and strong emphasis", "GFM strikethrough"]),
    ("links", ["Links", "Link reference definitions", "Autolinks", "GFM autolink"]),
    ("images", ["Images"]),
    ("code", ["Code spans", "Fenced code blocks", "Indented code blocks"]),
    ("html", ["HTML blocks", "Raw HTML", "GFM tagfilter"]),
    ("entities", ["Entity and numeric character references", "Backslash escapes"]),
    ("headings", ["ATX headings", "Setext headings"]),
    ("breaks", ["Hard line breaks", "Soft line breaks", "Thematic breaks"]),
]


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
        md, markup, target = [], [], None
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
    for item in json.loads(read("gfm-table-forms.json")):
        out.append({"markdown": item["markdown"], "html": item["html"], "section": item["section"], "example": "table-" + item["example"]})
    return out


def group_of(section):
    for name, sections in GROUPS:
        if section in sections:
            return name
    return "other"


def manifest(work, limit):
    rules = rule_of()
    mdDir = os.path.join(work, "md")
    os.makedirs(mdDir, exist_ok=True)
    listed = []
    for n, item in enumerate(examples()[:limit] if limit > 0 else examples()):
        with open(os.path.join(mdDir, "%d.md" % n), "w", encoding="utf-8") as handle:
            handle.write(item["markdown"])
        item["n"] = n
        item["group"] = group_of(item["section"])
        item["state"] = rules.get(item["example"], "pass")
        listed.append(item)
    with open(os.path.join(mdDir, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(listed, handle)
    print("manifest %d examples" % len(listed))


STYLE = """
body { margin: 0; padding: 12px; background: #fff; color: #1f2328; font: 14px/1.5 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
h1 { font-size: 18px; margin: 0 0 10px; }
.grid { display: grid; grid-template-columns: repeat(%(columns)d, 1fr); gap: 10px; }
.pair { border: 1px solid #d0d7de; border-radius: 6px; padding: 6px; break-inside: avoid; }
.label { font: 12px monospace; margin-bottom: 4px; }
.rule { color: #9a6700; }
.pass { color: #1a7f37; }
.cols { display: flex; gap: 8px; }
.col { width: %(width)dpx; overflow: hidden; }
.col .cap { font: 11px monospace; color: #656d76; margin-bottom: 2px; }
.flea { background: #101315; display: block; }
.spec { border: 1px solid #eaeef2; padding: 4px; }
.spec h1, .spec h2, .spec h3, .spec h4, .spec h5, .spec h6 { margin: 8px 0 4px; font-size: 1.2em; }
.spec p, .spec ul, .spec ol, .spec blockquote, .spec pre, .spec table { margin: 0 0 6px; }
.spec blockquote { padding: 0 8px; color: #656d76; border-left: 3px solid #d0d7de; }
.spec pre { background: #f6f8fa; padding: 6px; overflow: auto; }
.spec code { background: #f6f8fa; font-family: monospace; }
.spec table { border-collapse: collapse; }
.spec th, .spec td { border: 1px solid #d0d7de; padding: 3px 8px; }
.spec img { max-width: 100%%; }
.spec hr { border: 0; border-top: 1px solid #d0d7de; }
""" % {"columns": COLUMNS, "width": SPEC_WIDTH}


# Sample input: a sheet's examples answer one HTML page, each pair labelled "n. example number, section, pass or the rule".
def page(title, items, shots):
    cards = []
    for item in items:
        label = "%s &middot; %s &middot; %s" % (html.escape(str(item["example"])), html.escape(item["section"]),
                                                  '<span class="pass">pass</span>' if item["state"] == "pass" else '<span class="rule">rule: %s</span>' % html.escape(item["state"]))
        flea = '<img class="flea" src="file://%s">' % os.path.join(shots, "%d.png" % item["n"])
        if not os.path.exists(os.path.join(shots, "%d.png" % item["n"])):
            flea = '<div class="flea" style="color:#f66;padding:4px">no capture</div>'
        cards.append('<div class="pair"><div class="label">%s</div><div class="cols">'
                     '<div class="col"><div class="cap">Flea</div>%s</div>'
                     '<div class="col"><div class="cap">spec HTML</div><div class="spec">%s</div></div></div></div>'
                     % (label, flea, item["html"]))
    return "<!doctype html><meta charset=utf-8><style>%s</style><h1>%s</h1><div class=grid>%s</div>" % (STYLE, html.escape(title), "".join(cards))


def chromium(args, home):
    env = dict(os.environ, HOME=home)
    cmd = [CHROMIUM, "--headless", "--no-sandbox", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
           "--user-data-dir=" + os.path.join(home, "profile")] + args
    return subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=120)


# The page's height: a script writes it into the title and --dump-dom prints it back.
def height_of(path, home):
    probe = path + ".probe.html"
    with open(path, encoding="utf-8") as handle:
        body = handle.read()
    with open(probe, "w", encoding="utf-8") as handle:
        handle.write(body + "<script>window.onload=function(){document.title='H'+Math.ceil(document.body.getBoundingClientRect().height+24)}</script>")
    result = chromium(["--window-size=%d,2000" % window_width(), "--virtual-time-budget=2000", "--dump-dom", "file://" + probe], home)
    found = re.search(r"<title>H(\d+)</title>", result.stdout)
    return int(found.group(1)) if found else 2000


def window_width():
    return COLUMNS * (SPEC_WIDTH * 2 + 60) + 40


def sheets(work, out):
    work, out = os.path.abspath(work), os.path.abspath(out)
    listed = json.load(open(os.path.join(work, "md", "manifest.json"), encoding="utf-8"))
    shots = os.path.join(work, "shots")
    home = os.path.join(work, "home")
    os.makedirs(home, exist_ok=True)
    os.makedirs(out, exist_ok=True)
    for name in [group for group, _ in GROUPS] + ["other"]:
        queue = [[item for item in listed if item["group"] == name]]
        pieces = []
        # A sheet taller than one screenshot holds splits in half until each part fits.
        while queue and queue[0]:
            part = queue.pop(0)
            path = os.path.join(work, "%s-build-%d.html" % (name, len(pieces)))
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(page("%s (%d examples)" % (name, len(part)), part, shots))
            height = height_of(path, home)
            if height > MAX_PAGE_HEIGHT and len(part) > 1:
                half = len(part) // 2
                queue = [part[:half], part[half:]] + queue
                continue
            pieces.append((part, path, height))
        for index, (part, path, height) in enumerate(pieces):
            suffix = "" if len(pieces) == 1 else "-%d" % (index + 1)
            target = os.path.join(out, "%s%s.png" % (name, suffix))
            chromium(["--window-size=%d,%d" % (window_width(), min(height, MAX_PAGE_HEIGHT)), "--screenshot=" + target, "file://" + path], home)
            print("sheet %s (%d examples, height %d)" % (os.path.basename(target), len(part), height))


if __name__ == "__main__":
    if sys.argv[1] == "manifest":
        manifest(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0)
    elif sys.argv[1] == "sheets":
        sheets(sys.argv[2], sys.argv[3])
