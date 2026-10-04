#!/usr/bin/env python3
"""Markdown head-to-head fixtures: one plain ASCII document per matrix row that renders, plus a 1 MiB and a pathological one.

Usage: md-fixtures.py DIR      writes DIR/docs/*.md, DIR/docs/img, DIR/docs/sub, DIR/shared and prints the document names
       md-fixtures.py --list   prints the document names only, writes nothing
DIR must not exist. Documents are generated from fixed text and a seeded generator, so every run builds the same bytes.
"""
import random
import struct
import sys
import zlib
from pathlib import Path

# The 1 MiB document is padded to exactly this many bytes (Strata's parser input cap is "1 MiB").
LARGE_BYTES = 1048576
# Nesting depths of the pathological document, far past Strata's cap of 32 and any sane document.
QUOTE_DEPTH = 400
LIST_DEPTH = 300
BRACKET_DEPTH = 5000
EMPHASIS_PAIRS = 5000
# Seed of the 1 MiB document's block generator.
LARGE_SEED = 38
# Size of every generated PNG, in pixels.
PNG_W, PNG_H = 96, 64

WORDS = ("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega "
         "folder window preview render column paragraph heading cursor sidebar thumbnail archive listing watcher settle").split()


def png(path, rgb):
    """A solid colour with a diagonal gradient, written as a valid PNG with the standard library only."""
    rows = bytearray()
    for y in range(PNG_H):
        rows.append(0)
        for x in range(PNG_W):
            shade = (x + y) * 255 // (PNG_W + PNG_H)
            rows += bytes(((rgb[0] + shade) // 2, (rgb[1] + shade) // 2, (rgb[2] + shade) // 2))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    head = struct.pack(">IIBBBBB", PNG_W, PNG_H, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", head) + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))


DOCS = {}

DOCS["01-commonmark.md"] = """# CommonMark core

A paragraph with *emphasis*, **strong text**, ***both***, `inline code` and a [link](https://example.invalid/page "Title").
A second line in the same paragraph.
A hard break above, and a backslash break\\
right here.

## Second level

### Third level

#### Fourth level

Setext heading
==============

Another setext
--------------

> A block quote with **bold** inside.
>
> > Nested quote.

- Bullet one
- Bullet two
  - Nested bullet
    - Deeper bullet
- Bullet three

1. First
2. Second
   1. Nested first
   2. Nested second
3. Third

Loose list:

- Item with a paragraph

  Continued paragraph in the item.

- Second loose item

    indented code block

***

Autolink <https://example.invalid/auto> and an escaped \\*star\\*.
"""

DOCS["02-table.md"] = """# Tables

| Name | Size | Kind |
|:-----|-----:|:----:|
| alpha | 10 | file |
| beta | 200 | folder |
| gamma | 3000 | link |
| delta | 4 | file |

A table with inline markup:

| Column | Notes |
|---|---|
| `code` | **bold** and *italic* |
| [link](https://example.invalid) | plain text |

Text after the tables.
"""

DOCS["03-strike-task.md"] = """# Strikethrough and task lists

This is ~~struck through~~ text and this is not.

- [x] Done item
- [ ] Open item
- [x] Another done item
  - [ ] Nested open item
  - [x] Nested done item
- Plain bullet beside the tasks
"""

DOCS["04-footnotes.md"] = """# Footnotes

A sentence with a note.[^1] Another sentence with a named note.[^named]

A third reference to the first note.[^1]

[^1]: The first footnote text.
[^named]: The named footnote, with a second line
    that continues the text.
"""

DOCS["05-alert.md"] = """# GitHub alerts

> [!NOTE]
> Useful information that users should know.

> [!TIP]
> Helpful advice for doing things better.

> [!IMPORTANT]
> Key information users need to know.

> [!WARNING]
> Urgent info that needs immediate attention.

> [!CAUTION]
> Advises about risks or negative outcomes.

> A plain block quote for contrast.
"""

DOCS["06-frontmatter.md"] = """---
title: Front matter sample
author: Test Author
tags: [alpha, beta, gamma]
draft: false
---

# Document after the front matter

The block above is YAML front matter. Body text follows it.
"""

DOCS["07-rawhtml.md"] = """# Raw HTML

<p align="center"><img src="img/logo.png" width="64" alt="logo"></p>
<p align="center"><b>A centred title</b></p>

Line one<br>line two after a break. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy. Water is H<sub>2</sub>O and E = mc<sup>2</sup>.

<details>
<summary>Click to expand</summary>

Hidden body text inside details.

</details>

<div style="color: red">A div with a style attribute</div>

<script>alert("not allowed")</script>
"""

DOCS["08-remote-image.md"] = """# Remote images

![A remote picture](https://example.invalid/pictures/remote-one.png)

Text between the images.

![Another remote picture](http://example.invalid/pictures/remote-two.jpg "Second")
"""

DOCS["09-relative-image.md"] = """# Relative images

Same folder child:

![local](img/local.png)

Subfolder two levels down:

![deep](sub/deep/deeper.png)

Parent folder, outside the document's own folder:

![up](../shared/up.png)

Percent-encoded name:

![spaced](img/with%20space.png)
"""

DOCS["10-mermaid-flowchart.md"] = """# Mermaid flowchart

```mermaid
flowchart TD
    A[Start] --> B{Is it working?}
    B -->|Yes| C[Ship it]
    B -->|No| D[Debug]
    D --> B
    C --> E((Done))
```
"""

DOCS["11-mermaid-sequence.md"] = """# Mermaid sequence

```mermaid
sequenceDiagram
    participant A as Alice
    participant B as Bob
    A->>B: Hello Bob, how are you?
    B-->>A: Fine, thanks
    A->>B: See you later
```
"""

DOCS["12-maths.md"] = """# Maths

Inline: the identity $e^{i\\pi} + 1 = 0$ sits in a sentence, and so does $a^2 + b^2 = c^2$.

Display:

$$
\\int_0^1 x^2 \\, dx = \\frac{1}{3}
$$

A matrix:

$$
\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}
$$

A sum: $$\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}$$

Escaped dollars stay text: \\$5 and \\$10.
"""

DOCS["13-code-fence.md"] = """# Fenced code with a language

```rust
fn main() {
    let words = vec!["a", "b", "c"];
    for (i, w) in words.iter().enumerate() {
        println!("{} {}", i, w);
    }
}
```

```python
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

```bash
for f in *.md; do
  printf '%s\\n' "$f"
done
```

```javascript
const sum = (xs) => xs.reduce((a, b) => a + b, 0);
console.log(sum([1, 2, 3]));
```

```
a fence with no language
```
"""


def paragraph(rng):
    n = rng.randint(30, 90)
    text = " ".join(rng.choice(WORDS) for _ in range(n))
    return text[0].upper() + text[1:] + "."


def large_blocks(rng):
    """One block of the 1 MiB document, chosen by a seeded generator."""
    kind = rng.choice(("para", "para", "para", "heading", "list", "code", "quote", "table", "inline"))
    if kind == "para":
        return paragraph(rng)
    if kind == "heading":
        return "#" * rng.randint(1, 4) + " " + " ".join(rng.choice(WORDS) for _ in range(rng.randint(2, 6)))
    if kind == "list":
        return "\n".join("- " + " ".join(rng.choice(WORDS) for _ in range(rng.randint(3, 9))) for _ in range(rng.randint(3, 7)))
    if kind == "code":
        return "```rust\n" + "\n".join("let v%d = %d;" % (i, rng.randint(0, 9999)) for i in range(rng.randint(3, 8))) + "\n```"
    if kind == "quote":
        return "> " + paragraph(rng)
    if kind == "table":
        rows = ["| a | b | c |", "|---|---|---|"]
        rows += ["| %s | %s | %d |" % (rng.choice(WORDS), rng.choice(WORDS), rng.randint(0, 999)) for _ in range(rng.randint(2, 5))]
        return "\n".join(rows)
    words = [rng.choice(WORDS) for _ in range(rng.randint(8, 20))]
    return "A line with *%s* and **%s** and `%s` and [%s](https://example.invalid/%s) inside." % (words[0], words[1], words[2], words[3], words[4])


def build_large():
    rng = random.Random(LARGE_SEED)
    parts = ["# A 1 MiB document", ""]
    size = len("\n".join(parts)) + 1
    # Stop early enough that one padding paragraph reaches the exact size.
    margin = 4096
    while size < LARGE_BYTES - margin:
        block = large_blocks(rng)
        parts.append(block)
        parts.append("")
        size += len(block) + 2
    text = "\n".join(parts) + "\n"
    pad = LARGE_BYTES - len(text.encode("ascii")) - 1
    # A closing paragraph of plain words fills the gap, so the file is exactly LARGE_BYTES with a trailing newline.
    filler = ("closing " * (pad // 8 + 1))[:pad].rstrip()
    filler += "x" * (pad - len(filler))
    return text + filler + "\n"


def build_pathological():
    out = ["# Pathological nesting", ""]
    out.append("Block quotes %d deep:" % QUOTE_DEPTH)
    out.append("")
    for depth in range(1, QUOTE_DEPTH + 1):
        out.append("> " * depth + "level %d" % depth)
    out.append("")
    out.append("List items %d deep:" % LIST_DEPTH)
    out.append("")
    for depth in range(LIST_DEPTH):
        out.append("  " * depth + "- item %d" % depth)
    out.append("")
    out.append("Brackets:")
    out.append("")
    out.append("[" * BRACKET_DEPTH + "x" + "]" * BRACKET_DEPTH)
    out.append("")
    out.append("Emphasis delimiters, never closed:")
    out.append("")
    out.append("*a _b " * EMPHASIS_PAIRS)
    out.append("")
    return "\n".join(out) + "\n"


DOCS["14-large-1mib.md"] = None
DOCS["15-pathological.md"] = None
# Measurement order: the document names in numeric order.
NAMES = sorted(DOCS)


def main(argv):
    if len(argv) != 2:
        sys.exit("usage: md-fixtures.py DIR | --list")
    if argv[1] == "--list":
        print("\n".join(NAMES))
        return 0
    root = Path(argv[1])
    if root.exists():
        sys.exit("md-fixtures: %s already exists" % root)
    docs = root / "docs"
    (docs / "img").mkdir(parents=True)
    (docs / "sub" / "deep").mkdir(parents=True)
    (root / "shared").mkdir()
    png(docs / "img" / "logo.png", (200, 60, 60))
    png(docs / "img" / "local.png", (60, 140, 200))
    png(docs / "img" / "with space.png", (200, 160, 40))
    png(docs / "sub" / "deep" / "deeper.png", (60, 180, 100))
    png(root / "shared" / "up.png", (150, 80, 190))
    for name in NAMES:
        text = DOCS[name]
        if text is None:
            text = build_large() if name.startswith("14-") else build_pathological()
        data = text.encode("ascii")
        (docs / name).write_bytes(data)
    large = (docs / "14-large-1mib.md").stat().st_size
    if large != LARGE_BYTES:
        sys.exit("md-fixtures: the large document is %d bytes, wanted %d" % (large, LARGE_BYTES))
    print("\n".join(NAMES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
