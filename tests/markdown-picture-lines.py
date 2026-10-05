#!/usr/bin/env python3
# Judges the picture lines the table suite grabbed from one name label json record per stdin line: each picture sits inside its own line, row and block.
import json
import os
import struct
import sys
import zlib

# The solid fill tests/markdown-tables-assets.sh paints every picture with.
PICTURE = (0x40, 0x80, 0xC0)
# Layout rounds to whole pixels, so a picture may end this far below its block without overlapping anything.
ROUNDING = 1
# A row keeps no more than this under a one-line picture: the font's descent and the cell's own padding, never the proportional stretch.
TAIL = 10
# The cases whose picture is the 400 px one; every other case draws the 160 px one.
WIDE_PICTURE = {"picwide": "huge.png", "picwidelist": "huge.png"}
# A case's twin draws the same document with the 12 px dot where the picture is, as markdown-tables.sh writes it.
TWIN = "-dot"
COLOR_TYPE_RGBA = 6


# Sample input: "tables-picfirst-card.png" answers (width, height, step, rows) for that frame.
def read_png(path):
    data = open(path, "rb").read()
    at = 8
    idat = b""
    while at < len(data):
        size, tag = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + size]
        at += 12 + size
        if tag == b"IHDR":
            width, height, _depth, kind = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
    step = 4 if kind == COLOR_TYPE_RGBA else 3
    raw = zlib.decompress(idat)
    stride = width * step
    rows = []
    prev = bytearray(stride)
    at = 0
    for _ in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - step] if i >= step else 0
            b = prev[i]
            c = prev[i - step] if i >= step else 0
            if filt == 1:
                line[i] = (line[i] + a) & 255
            elif filt == 2:
                line[i] = (line[i] + b) & 255
            elif filt == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return width, height, step, rows


def natural_size(path):
    # The picture file's own size, from its PNG header.
    with open(path, "rb") as f:
        return struct.unpack(">II", f.read(24)[16:24])


def pixel(rows, step, x, y):
    at = x * step
    return tuple(rows[y][at:at + 3])


def picture_box(width, height, step, rows):
    x0, y0, x1, y1 = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            if pixel(rows, step, x, y) == PICTURE:
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
    return None if x1 < 0 else (x0, y0, x1 + 1, y1 + 1)


def ink_pixels(rows, step, rect, background):
    count = 0
    for y in range(max(0, rect["y"]), min(len(rows), rect["y"] + rect["h"])):
        for x in range(max(0, rect["x"]), min(len(rows[0]) // step, rect["x"] + rect["w"])):
            px = pixel(rows, step, x, y)
            if px != PICTURE and px != background:
                count += 1
    return count


# Sample input: {"bg": "#101315"} answers (0x10, 0x13, 0x15).
def background_of(ink):
    return tuple(int(ink["bg"][-6:][i:i + 2], 16) for i in (0, 2, 4))


def ink_bottom_above(rows, step, row, columns, background):
    # The lowest row above `row` holding any ink in the text's columns (a rule counts, a quote bar or a bullet beside them does not), or -1 when bare.
    for y in range(row - 1, -1, -1):
        for x in range(max(0, columns[0]), min(len(rows[y]) // step, columns[1])):
            if pixel(rows, step, x, y) != background:
                return y
    return -1


# Sample input: rows holding text under the box answer the rows from the picture's bottom edge to the block's, text and rules included.
def empty_below(rows, step, box_bottom, holder, background):
    # Wrapped lines and rules below end the count, so only empty stretch fails it.
    last = -1
    bottom = min(len(rows), holder["y"] + holder["h"])
    for y in range(max(0, box_bottom), bottom):
        for x in range(max(0, holder["x"]), min(len(rows[0]) // step, holder["x"] + holder["w"])):
            px = pixel(rows, step, x, y)
            if px != PICTURE and px != background:
                last = y
                break
    if last < 0:
        return bottom - box_bottom
    return bottom - (last + 1)


def judge(label, ink, frame, twin_ink, twin_frame, natural_file):
    width, height, step, rows = read_png(frame)
    twin_width, twin_height, twin_step, twin_rows = read_png(twin_frame)
    holders = [t for t in ink["texts"] if t["picture"]]
    if len(holders) != 1:
        return "%d texts hold a picture, not 1" % len(holders)
    holder = holders[0]
    box = picture_box(width, height, step, rows)
    small = picture_box(twin_width, twin_height, twin_step, twin_rows)
    if box is None or small is None:
        return "no picture was drawn"
    # The twin draws the same document with a picture that fits its line, so the ink above its top is what the big one must clear.
    above = ink_bottom_above(twin_rows, twin_step, small[1], (holder["x"], holder["x"] + holder["w"]), background_of(twin_ink))
    if box[1] <= above:
        return "the picture starts at y %d, over ink the line above draws down to y %d" % (box[1], above)
    if box[3] > holder["y"] + holder["h"] + ROUNDING:
        return "the picture ends at y %d, %d px below its block at y %d" % (box[3], box[3] - holder["y"] - holder["h"], holder["y"] + holder["h"])
    # A picture wider than its text is scaled to the text's width with its ratio kept; the pane clips a wider one, so its height gives it away.
    natural_w, natural_h = natural_size(natural_file)
    wanted_w = min(natural_w, holder["w"])
    wanted_h = natural_h * wanted_w / natural_w
    # A capped picture draws within ROUNDING of the wanted width on both sides; a narrower one is a scale the pane never asked for.
    if abs(box[2] - box[0] - wanted_w) > ROUNDING or abs(box[3] - box[1] - wanted_h) > ROUNDING:
        return "the picture draws %d by %d, not %d by %d: it is not scaled to the %d px of its text" % (box[2] - box[0], box[3] - box[1], wanted_w, wanted_h, holder["w"])
    # A one-line text keeps no more than the tail below its picture inside its own block, the same bound the table tail check uses.
    gap = empty_below(rows, step, box[3], holder, background_of(ink))
    if gap > TAIL:
        return "the block keeps %d px under its picture, more than %d" % (gap, TAIL)
    rules = sorted(ink["rules"], key=lambda r: r["y"])
    below = [r for r in rules if r["y"] >= box[3] - ROUNDING]
    # The narrow column may legitimately wrap the text after a picture capped to its width, so only the card's row is held to the tail.
    if label == "card" and below and below[0]["y"] - box[3] > TAIL:
        return "the row keeps %d px under its picture, more than %d" % (below[0]["y"] - box[3], TAIL)
    for cell in [t for t in ink["texts"] if rules and t["y"] + t["h"] <= rules[0]["y"] + ROUNDING]:
        if box[0] < cell["x"] + cell["w"] and box[2] > cell["x"] and box[1] < cell["y"] + cell["h"] and box[3] > cell["y"]:
            return "the picture reaches y %d, over the header text at x %d" % (box[1], cell["x"])
        if ink_pixels(rows, step, cell, background_of(ink)) == 0:
            return "the header text at x %d is covered or never drawn" % cell["x"]
    return ""


def main():
    runtime, docs = sys.argv[1], sys.argv[2]
    records = {}
    for line in sys.stdin:
        # Sample input: "picfirst card {\"texts\": [...], \"rules\": [...]}" names the case, the label and its rects.
        name, label, body = line.rstrip("\n").split(" ", 2)
        records[(name, label)] = json.loads(body)
    failed = 0
    judged = 0
    for (name, label), ink in sorted(records.items()):
        twin = records.get((name + TWIN, label))
        if twin is None:
            continue
        judged += 1
        frame = lambda case: os.path.join(runtime, "tables-%s-%s.png" % (case, label))
        error = judge(label, ink, frame(name), twin, frame(name + TWIN), os.path.join(docs, WIDE_PICTURE.get(name, "wide.png")))
        failed += 1 if error != "" else 0
        print(("FAIL" if error != "" else "ok") + " picture line %s %s: %s" % (name, label, error or "clear of the ink above, inside its own block"))
    if judged == 0:
        print("FAIL picture line: no case had a twin to judge against")
        failed += 1
    sys.exit(1 if failed else 0)


main()
