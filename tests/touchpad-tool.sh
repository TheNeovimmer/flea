#!/usr/bin/env bash
# Headless gate for tools/flea-touchpad: create() and swipe() run with fcntl.ioctl and
# os.open/os.write replaced by recorders, so no /dev/uinput is needed. Fails on the old
# create(), which passed packed buffers to UI_SET_*BIT, wrote the legacy uinput_user_dev
# layout to UI_DEV_SETUP, and left ABS_MT_SLOT and ABS_MT_TRACKING_ID without absinfo.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
export PYTHONDONTWRITEBYTECODE=1  # importing the tool must not litter tools/__pycache__

python3 - "${1:-$PWD/tools/flea-touchpad}" <<'PYEOF'
import importlib.util
import struct
import sys
from importlib.machinery import SourceFileLoader

spec = importlib.util.spec_from_loader("flea_touchpad", SourceFileLoader("flea_touchpad", sys.argv[1]))
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

import fcntl
import os
import time

calls = []
written = []

def fake_ioctl(fd, req, arg=None):
    calls.append((req, arg))
    return 0

def fake_open(path, flags, *args):
    return 99

def fake_write(fd, data):
    written.append(bytes(data))
    return len(data)

fcntl.ioctl = fake_ioctl
os.open = fake_open
os.write = fake_write
time.sleep = lambda s: None

fails = []

def fail(msg):
    fails.append(msg)
    print("touchpad-tool: FAIL " + msg)

fd = tp.create()
tp.swipe(fd, 0.0, 40.0, 120, 0)
tp.swipe(fd, 0.0, 40.0, 120, 200)

SETBITS = (tp.UI_SET_EVBIT, tp.UI_SET_KEYBIT, tp.UI_SET_ABSBIT, tp.UI_SET_PROPBIT)

# SET-bit ioctls take the bit number by value, so the arg must be an int, not a buffer.
for req, arg in calls:
    if req in SETBITS and not isinstance(arg, int):
        fail("req %#x passes %s, not an int" % (req, type(arg).__name__))

# Every buffer arg matches the size the request number encodes in bits 16..29.
for req, arg in calls:
    if isinstance(arg, (bytes, bytearray, memoryview)):
        want = (req >> 16) & 0x3fff
        if len(arg) != want:
            fail("req %#x buffer is %d bytes, request encodes %d" % (req, len(arg), want))

# UI_DEV_SETUP carries struct uinput_setup naming this device.
setups = [a for r, a in calls if r == tp.UI_DEV_SETUP]
if len(setups) != 1:
    fail("UI_DEV_SETUP called %d times, want 1" % len(setups))
else:
    try:
        name = struct.unpack("HHHH80sI", setups[0])[4].split(b"\x00")[0]
    except struct.error as e:
        fail("UI_DEV_SETUP buffer does not unpack as uinput_setup: %s" % e)
        name = None
    if name is not None and name != b"flea-touchpad":
        fail("UI_DEV_SETUP name reads %r, want b'flea-touchpad'" % (name,))

# Every axis declared with UI_SET_ABSBIT has a UI_ABS_SETUP with maximum above 0.
declared = [a for r, a in calls if r == tp.UI_SET_ABSBIT]
infos = {}
for r, a in calls:
    if r == tp.UI_ABS_SETUP:
        code, _, _, maximum, _, _, _ = struct.unpack("Iiiiiii", a)
        infos[code] = maximum
for code in declared:
    if not isinstance(code, int):
        continue
    if infos.get(code, 0) <= 0:
        fail("ABS code %d has no UI_ABS_SETUP with maximum above 0" % (code,))

# Every written event is one struct input_event, 24 bytes.
for i, data in enumerate(written):
    if len(data) != 24:
        fail("write %d is %d bytes, want 24" % (i, len(data)))
if not written:
    fail("swipe() wrote no events")

if fails:
    sys.exit(1)
print("touchpad-tool: PASS ioctls=%d writes=%d axes=%d" % (len(calls), len(written), len(infos)))
PYEOF
