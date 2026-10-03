# The real launcher reaches exec with a present but non-executable prlimit.
import os
import pathlib
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="flea-figure-start-") as scratch:
    root = pathlib.Path(scratch)
    for name in ("prlimit", "bwrap", "qjs"):
        (root / name).write_text("present but not executable\n")
    env = dict(os.environ, PATH=str(root), FLEA_QJS=str(root / "qjs"))
    result = subprocess.run([binary, "--figure-helper"], env=env, capture_output=True, text=True, timeout=5)
    checks = [
        (result.returncode == 127, "exec failure refuses with 127"),
        ("prlimit" in result.stderr, "exec failure names argv[0] prlimit"),
        ("Permission denied" in result.stderr and "os error 13" in result.stderr, "exec failure names the OS error"),
    ]
    for passed, label in checks:
        print(("PASS " if passed else "FAIL ") + label)
    failures = sum(not passed for passed, _ in checks)
    print(f"figure-helper-start: {len(checks)} check(s), {failures} failed")
    sys.exit(bool(failures))
