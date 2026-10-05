#!/usr/bin/env python3
"""Judges tests/markdown-taskbox.qml's picture: both task boxes are grey text glyphs of one size, never a colour emoji."""
import struct
import sys
import zlib

ROW_HEIGHT = 40
BOX_COLUMNS = 20
INK_FLOOR = 60
# A colour emoji carries hue; a text glyph in the row's grey carries none.
CHROMA_LIMIT = 8
SIZE_TOLERANCE = 1
PNG_HEADER = 8
CHUNK_FRAME = 12


def decode(path):
    data = open(path, "rb").read()
    at, idat, width, height, kind = PNG_HEADER, b"", 0, 0, 0
    while at < len(data):
        size, tag = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + size]
        if tag == b"IHDR":
            width, height, _, kind = struct.unpack(">IIBB", body[:10])
        if tag == b"IDAT":
            idat += body
        at += CHUNK_FRAME + size
    raw = zlib.decompress(idat)
    step = {2: 3, 6: 4}[kind]
    stride = width * step
    rows, previous, cursor = [], bytearray(stride), 0
    for _ in range(height):
        method, line = raw[cursor], bytearray(raw[cursor + 1:cursor + 1 + stride])
        cursor += 1 + stride
        for x in range(stride):
            left = line[x - step] if x >= step else 0
            up = previous[x]
            corner = previous[x - step] if x >= step else 0
            if method == 1:
                line[x] = (line[x] + left) & 255
            elif method == 2:
                line[x] = (line[x] + up) & 255
            elif method == 3:
                line[x] = (line[x] + (left + up) // 2) & 255
            elif method == 4:
                guess = left + up - corner
                near = min((abs(guess - left), left), (abs(guess - up), up), (abs(guess - corner), corner))[1]
                line[x] = (line[x] + near) & 255
        rows.append(line)
        previous = line
    return rows, step


def measure(rows, step, row):
    chroma, left, right, top, bottom = 0, 1 << 30, -1, 1 << 30, -1
    for y in range(row * ROW_HEIGHT, (row + 1) * ROW_HEIGHT):
        for x in range(BOX_COLUMNS):
            r, g, b = rows[y][x * step:x * step + 3]
            if max(r, g, b) > INK_FLOOR:
                chroma = max(chroma, max(r, g, b) - min(r, g, b))
                left, right, top, bottom = min(left, x), max(right, x), min(top, y), max(bottom, y)
    return chroma, right - left + 1, bottom - top + 1


def main():
    rows, step = decode(sys.argv[1])
    failures = 0
    sizes = []
    for row, name in enumerate(("open", "done")):
        chroma, width, height = measure(rows, step, row)
        sizes.append((width, height))
        ok = width > 0 and chroma <= CHROMA_LIMIT
        print("%s task box: chroma %d, %dx%d px%s" % (name, chroma, width, height, "" if ok else " FAIL not a grey text glyph"))
        failures += 0 if ok else 1
    if abs(sizes[0][0] - sizes[1][0]) > SIZE_TOLERANCE or abs(sizes[0][1] - sizes[1][1]) > SIZE_TOLERANCE:
        print("FAIL the open and the done box differ in size: %dx%d against %dx%d" % (sizes[0] + sizes[1]))
        failures += 1
    print("MARKDOWN_TASKBOX %d failed" % failures)
    sys.exit(1 if failures else 0)


main()
