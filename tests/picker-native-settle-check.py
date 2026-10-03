#!/usr/bin/env python3
"""Exercise the native runner's settled-picture helper with a fake shooter, without GI or a display."""
import ast
from pathlib import Path
import time

source = ast.parse(Path(__file__).with_name("picker-native.py").read_text())
CONSTANTS = {"SETTLE_SHOT_INTERVAL_S", "SETTLE_MAX_SHOTS"}
constants = [node for node in source.body if isinstance(node, ast.Assign)
             and any(isinstance(target, ast.Name) and target.id in CONSTANTS for target in node.targets)]
helper = next((node for node in source.body if isinstance(node, ast.FunctionDef) and node.name == "settled_picture"), None)
if helper is None or len(constants) != len(CONSTANTS):
    raise SystemExit("FAIL picker-native-settle-check: missing settled_picture helper or its two constants in picker-native.py")
namespace = dict(time=time)
exec(compile(ast.Module(body=[*constants, helper], type_ignores=[]), "picker-native.py", "exec"), namespace)
settled_picture = namespace["settled_picture"]
interval = namespace["SETTLE_SHOT_INTERVAL_S"]
limit = namespace["SETTLE_MAX_SHOTS"]

checks = 0
failures = 0


def check(label, action):
    global checks, failures
    checks += 1
    try:
        action()
        print("PASS " + label)
    except Exception as error:
        failures += 1
        print("FAIL " + label + ": " + str(error))


def drive(pictures):
    # Returns what the helper kept, how many shots it took and every wait it asked for; the fake sleeps nothing.
    shots, waits = [], []
    sequence = iter(pictures)
    def shoot():
        shots.append(next(sequence))
        return shots[-1]
    return settled_picture("SP-fake-state", shoot, sleep=waits.append), len(shots), waits


def two_equal_shots():
    kept, shots, waits = drive([b"still", b"still"])
    assert (kept, shots, waits) == (b"still", 2, [interval]), (kept, shots, waits)


def retries_while_changing():
    kept, shots, waits = drive([b"sliding", b"nearer", b"parked", b"parked"])
    assert (kept, shots, waits) == (b"parked", 4, [interval] * 3), (kept, shots, waits)


def caret_blinking_every_shot():
    # A caret that flips between every shot until the last pair, the worst blink the bound has to cover.
    flipping = [b"caret-on" if shot % 2 == 0 else b"caret-off" for shot in range(limit - 1)]
    kept, shots, waits = drive(flipping + [flipping[-1]])
    assert kept == flipping[-1] and shots == limit, (kept, shots, limit)


def never_settles():
    shots = []
    def shoot():
        shots.append(len(shots))
        return str(len(shots)).encode()
    try:
        settled_picture("SP09-backend-open-unavailable", shoot, sleep=lambda seconds: None)
    except AssertionError as error:
        assert "SP09-backend-open-unavailable" in str(error), "the failure did not name the state: " + str(error)
        assert str(limit) in str(error), "the failure did not name the bound: " + str(error)
        assert len(shots) == limit, "the helper stopped after " + str(len(shots)) + " shots, not at the bound " + str(limit)
        return
    raise AssertionError("a picture that never settled was accepted")


def capture_uses_the_helper():
    # Sample input: class Request: def capture(self, label): ... settled_picture(f"{self.name}-{label}", shoot).
    capture = next((node for cls in source.body if isinstance(cls, ast.ClassDef) and cls.name == "Request"
                    for node in cls.body if isinstance(node, ast.FunctionDef) and node.name == "capture"), None)
    assert capture is not None, "Request.capture is missing"
    calls = [node.func.id for node in ast.walk(capture) if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)]
    assert "settled_picture" in calls, "Request.capture shoots without waiting for the picture to settle"


check("two equal shots in a row settle at once", two_equal_shots)
check("a sliding window is shot again until it stops", retries_while_changing)
check("a caret flipping on every shot still settles inside the bound", caret_blinking_every_shot)
check("a picture that never settles fails at the bound naming its state", never_settles)
check("Request.capture waits through the helper", capture_uses_the_helper)
print(f"picker-native-settle-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
