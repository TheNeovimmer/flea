# The real launcher reaches exec with a present but non-executable prlimit.
import os
import pathlib
import subprocess
import sys
import tempfile

# A helper that never exits fails the check instead of hanging the suite.
HELPER_EXIT_BOUND_SECONDS = 5
# Print only the first bounded excerpt from each captured stream after failure.
HELPER_DIAGNOSTIC_LIMIT_CHARS = 4096


def diagnostics(result):
    for name, output in (("stdout", result.stdout), ("stderr", result.stderr)):
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        print(f"helper {name} (first {HELPER_DIAGNOSTIC_LIMIT_CHARS} characters):")
        print((output or "")[:HELPER_DIAGNOSTIC_LIMIT_CHARS])


binary = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="flea-figure-start-") as scratch:
    root = pathlib.Path(scratch)
    for name in ("prlimit", "bwrap", "qjs"):
        (root / name).write_text("present but not executable\n")
    env = dict(os.environ, PATH=str(root), FLEA_QJS=str(root / "qjs"))
    # No home and no cache dir, so the launcher starts no background build and writes nothing outside this scratch.
    env.pop("HOME", None)
    env.pop("XDG_CACHE_HOME", None)
    env["FLEA_UI"] = env.get("FLEA_UI") or str(pathlib.Path(__file__).resolve().parents[1] / "ui")
    try:
        result = subprocess.run([binary, "--figure-helper"], env=env, capture_output=True, text=True, timeout=HELPER_EXIT_BOUND_SECONDS)
    except subprocess.TimeoutExpired as error:
        print(f"FAIL helper did not exit within {HELPER_EXIT_BOUND_SECONDS} seconds")
        diagnostics(error)
        sys.exit(1)
    checks = [
        (result.returncode == 127, "exec failure refuses with 127"),
        ("prlimit" in result.stderr, "exec failure names argv[0] prlimit"),
        ("Permission denied" in result.stderr and "os error 13" in result.stderr, "exec failure names the OS error"),
    ]
    for passed, label in checks:
        print(("PASS " if passed else "FAIL ") + label)
    failures = sum(not passed for passed, _ in checks)
    if failures:
        diagnostics(result)
    print(f"figure-helper-start: {len(checks)} check(s), {failures} failed")
    sys.exit(bool(failures))
