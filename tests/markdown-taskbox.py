#!/usr/bin/env python3
"""Judges tests/markdown-taskbox.qml's picture: both task boxes are grey text glyphs of one size, never a colour emoji."""
import shutil
import struct
import subprocess
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


# PNG spec order: the left byte wins a tie with up or upper-left, then up wins a tie with upper-left.
def paeth(left, up, corner):
    guess = left + up - corner
    near_left, near_up, near_corner = abs(guess - left), abs(guess - up), abs(guess - corner)
    if near_left <= near_up and near_left <= near_corner:
        return left
    return up if near_up <= near_corner else corner


def decode(data):
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
                line[x] = (line[x] + paeth(left, up, corner)) & 255
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


# Sample input: two RGB pixels, row 0 unfiltered (60 then 40), row 1 Paeth: the second byte sees left 100, up 40, upper-left 60 (pa 20, pb 40, pc 20), so left wins and 50 + 100 = 150.
def selftest():
    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))
    raw = bytes([0] + [60] * 3 + [40] * 3 + [4] + [40] * 3 + [50] * 3)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    rows, _ = decode(png)
    want = [[60] * 3 + [40] * 3, [100] * 3 + [150] * 3]
    if [list(r) for r in rows] != want:
        print("FAIL the PNG decoder breaks a Paeth tie: %s against %s" % ([list(r) for r in rows], want))
        sys.exit(1)
    print("ok the PNG decoder takes the left byte on a Paeth tie")


# ffmpeg decodes the PNG on its own, so its raw pixels judge every byte this decoder reads from Qt's picture.
def crosscheck(path):
    if shutil.which("ffmpeg") is None:
        print("SKIP the PNG decoder cross-check: ffmpeg is not installed")
        return
    rows, step = decode(open(path, "rb").read())
    pix_fmt = "rgb24" if step == 3 else "rgba"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", pix_fmt, "-"], capture_output=True, check=True).stdout
    mine = b"".join(bytes(r) for r in rows)
    if raw != mine:
        print("FAIL the PNG decoder disagrees with ffmpeg on %d of %d bytes" % (sum(a != b for a, b in zip(raw, mine)), len(raw)))
        sys.exit(1)
    print("ok the PNG decoder matches ffmpeg on every pixel")


def main():
    selftest()
    crosscheck(sys.argv[1])
    rows, step = decode(open(sys.argv[1], "rb").read())
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
