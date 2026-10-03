#!/usr/bin/env python3
"""Pin each refusal scenario to its named operation and independent retry count."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

HELPER = Path(__file__).with_name("picker-focus-helper.py")
TIMEOUT_SECONDS = 5
OPERATIONS = ("mark", "validate", "review")
checks = 0
failures = 0

for refused in OPERATIONS:
    scenario = "refuse-" + refused
    preceding = [operation for operation in OPERATIONS if operation != refused]
    requests = [{"c": "picker", "op": operation, "id": index}
                for index, operation in enumerate(preceding + [refused, refused])]
    with tempfile.TemporaryDirectory(prefix="picker-helper-refusal-log-") as scratch:
        log = Path(scratch) / "refused-operations"
        result = subprocess.run(["python3", "-B", str(HELPER)],
                                input="".join(json.dumps(request) + "\n" for request in requests),
                                env=dict(os.environ, FLEA_PICKER_HUNT_CASE=scenario,
                                         FLEA_PICKER_HUNT_REFUSAL_LOG=str(log),
                                         FLEA_PICKER=json.dumps({"folder": str(HELPER.parent.resolve())})),
                                text=True, capture_output=True, check=False, timeout=TIMEOUT_SECONDS)
        logged_operations = log.read_text().splitlines() if log.exists() else []
    # Sample stdout: {"t":"picker","id":0,"op":"mark","ok":true,"marks":[...]}.
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    expected = [(operation, operation != refused or index == len(requests) - 1)
                for index, operation in enumerate(preceding + [refused, refused])]
    got = [(reply.get("op"), reply.get("ok")) for reply in replies]
    checks += 1
    ok = result.returncode == 0 and got == expected and logged_operations == [refused]
    failures += not ok
    print(("PASS " if ok else "FAIL ") + scenario + " refuses only " + refused
          + " once: got=" + str(got) + " expected=" + str(expected))

source = HELPER.with_name("picker-hunt.sh").read_text()
# Sample source: code=$? begins the verdict; the next outer done ends its scenario body.
begin = source.index("        code=$?")
classify = source[begin:source.index("    done", begin)]
with tempfile.TemporaryDirectory(prefix="picker-refused-operation-") as scratch:
    phase = Path(scratch)
    (phase / "reply.json").write_text(json.dumps({"response": 0, "uris": [(phase / "a.txt").as_uri()]}))
    for operation in ("mark", "validate"):
        (phase / "refused-operations").write_text(operation + "\n")
        output = "\n".join(["PICKER_HUNT DONE 1 checks, 0 failed",
                            "PICKER_HUNT RETRY Enter after refusal",
                            "PICKER_HUNT REFUSED " + operation])
        script = """set -uo pipefail
phase=$1
fixture=$phase
preset=default
view=list
scenario=refuse-validate
failures=0
phases=0
output=$2
true
""" + classify + '\n[ "$failures" -eq 0 ]\n'
        result = subprocess.run(["bash", "-c", script, "check", scratch, output],
                                text=True, capture_output=True, check=False, timeout=TIMEOUT_SECONDS)
        checks += 1
        ok = (result.returncode == 0) == (operation == "validate")
        failures += not ok
        print(("PASS " if ok else "FAIL ") + "refuse-validate logged " + operation
              + " classifier exit=" + str(result.returncode))

print(f"picker-focus-helper-check: {checks} checks, {failures} failed")
raise SystemExit(bool(failures))
