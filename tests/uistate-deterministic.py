#!/usr/bin/env python3
"""Deterministic interrupted ui.json proof; called inside uistate.sh guarded sandbox."""
import fcntl
import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1]).resolve()
binary = str(Path(sys.argv[2]).resolve())
assert root.name.startswith("flea-uistate-det-")
assert (root / ".flea-test-sandbox").is_file()
assert not root.is_relative_to(Path.home().resolve())
assert Path(binary).is_file()
library = root / "write-block.so"
subprocess.run(["cc", "-shared", "-fPIC", "-o", str(library),
                str(Path(__file__).with_name("uistate-write-block.c")), "-ldl"], check=True)

digest = hashlib.sha256(Path(binary).read_bytes()).hexdigest()
print(f"deterministic binary sha256={digest}", flush=True)

def run_flea(state, config, patch, extra_env):
    env = dict(os.environ, XDG_STATE_HOME=str(state),
               XDG_CONFIG_HOME=str(config))
    env.update(extra_env)
    return subprocess.Popen([binary, "--ui-state", patch], env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)

def wait_path(path, deadline_s, label):
    end = time.monotonic() + deadline_s
    while not path.exists():
        assert time.monotonic() < end, f"{label} missing: {path}"
        time.sleep(0.005)

# The child must prove it reached the lock step, or the kill below proves nothing.
def wait_lock_held(pid, lock_str, deadline_s):
    procdir = Path(f"/proc/{pid}/fd")
    end = time.monotonic() + deadline_s
    while True:
        assert time.monotonic() < end, f"child {pid} never opened the lock {lock_str}"
        try:
            names = os.listdir(procdir)
        except OSError as e:
            raise AssertionError(f"cannot list {procdir}, so the lock wait proves nothing: {e!r}")
        for name in names:
            try:
                if os.readlink(procdir / name) == lock_str:
                    return
            except OSError:
                continue
        time.sleep(0.005)

def read_bytes(path):
    return Path(path).read_bytes()

# Bounded budgets: reap wait, fake-child length, and fake-child timeout.
REAP_TIMEOUT = 10
FAKE_SLEEP_SECS = 30
FAKE_TIMEOUT = 0.2

def reap_owned(proc, label):
    try:
        proc.wait(timeout=REAP_TIMEOUT)
    except Exception as e:
        raise AssertionError(f"{label} reap failed after timeout: {e!r}") from None

def communicate_owned(proc, timeout, label):
    try:
        return proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        if proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass
        reap_owned(proc, label)
        raise AssertionError(f"{label} timed out, owned child killed/reaped") from None
    except BaseException:
        if proc.poll() is None:
            try:
                proc.kill()
            except OSError:
                pass
            try:
                proc.wait(timeout=REAP_TIMEOUT)
            except Exception:
                pass
        raise
    finally:
        for stream in (proc.stdout, proc.stderr):
            try:
                if stream is not None:
                    stream.close()
            except Exception:
                pass

def run_once(state, config, patch, label):
    proc = run_flea(state, config, patch, {})
    out, err = communicate_owned(proc, 10, label)
    assert proc.returncode == 0, f"{label} failed: {proc.returncode} {err}"
    return out

# Bounded fake-child control: a timeout on an owned sleep leaves no owned process behind.
_fake = subprocess.Popen(["sleep", str(FAKE_SLEEP_SECS)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    communicate_owned(_fake, FAKE_TIMEOUT, "fake sleep")
    raise AssertionError("fake sleep exited early, so the timeout control proves nothing")
except AssertionError as e:
    assert "timed out" in str(e), f"fake control misfired: {e}"
    assert _fake.poll() is not None, "fake child still owned after kill/reap"
    print("ok   timeout control reaped its owned sleep", flush=True)
finally:
    if _fake.poll() is None:
        _fake.kill()
        _fake.wait(timeout=REAP_TIMEOUT)

# Unexpected-error control: an odd communicate failure keeps its own reason while draining.
_boom = subprocess.Popen(["sleep", str(FAKE_SLEEP_SECS)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def _boom_fail(*args, **kwargs):
    raise RuntimeError("boom")
_boom.communicate = _boom_fail
try:
    communicate_owned(_boom, 10, "boom control")
    raise AssertionError("boom control did not raise, so honest diagnostics prove nothing")
except RuntimeError as e:
    assert "boom" in str(e), f"boom control misfired: {e}"
    # Cached returncode performs no reap, so a drain that skipped its wait reads None here.
    assert _boom.returncode is not None, "boom child still owned after drain"
    print("ok   unexpected error kept its reason and drained its child", flush=True)
finally:
    if _boom.poll() is None:
        _boom.kill()
        _boom.wait(timeout=REAP_TIMEOUT)

# Reap-error control: a timeout plus a wait that cannot reap is reported, never swallowed.
_stuck = subprocess.Popen(["sleep", str(FAKE_SLEEP_SECS)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
_real_stuck_wait = _stuck.wait
def _stuck_comm(*args, **kwargs):
    raise subprocess.TimeoutExpired("sleep", FAKE_TIMEOUT)
def _stuck_wait(*args, **kwargs):
    raise OSError("cannot reap")
_stuck.communicate = _stuck_comm
_stuck.wait = _stuck_wait
try:
    communicate_owned(_stuck, FAKE_TIMEOUT, "stuck control")
    raise AssertionError("stuck control did not raise, so reap honesty proves nothing")
except AssertionError as e:
    assert "reap failed" in str(e), f"stuck control misfired: {e}"
    print("ok   reap failure reported instead of claimed killed", flush=True)
finally:
    _stuck.wait = _real_stuck_wait
    if _stuck.poll() is None:
        _stuck.kill()
        _stuck.wait(timeout=REAP_TIMEOUT)

# Reference run without barrier gives the exact complete expected state.
ref_state = root / "ref" / "state"
ref_config = root / "ref" / "config"
ref_state.mkdir(parents=True)
ref_config.mkdir(parents=True)
ref_ui = ref_state / "flea" / "ui.json"
run_once(ref_state, ref_config, '{"view":"list"}', "reference seed")
run_once(ref_state, ref_config, '{"view":"grid"}', "reference patch")
expected = read_bytes(ref_ui)
assert b'"view": "grid"' in expected, f"reference state incomplete: {expected[:200]!r}"

# Stage before the temp exists: the parent holds the lock, so the child blocks in take_lock.
case0 = root / "before"
state0 = case0 / "state"
config0 = case0 / "config"
(state0 / "flea").mkdir(parents=True)
config0.mkdir(parents=True)
run_once(state0, config0, '{"view":"list"}', "before seed")
before0 = read_bytes(state0 / "flea" / "ui.json")
before0_ino = (state0 / "flea" / "ui.json").stat().st_ino
lock0 = str(state0 / "flea" / "ui.json.lock")
lock_fd = os.open(lock0, os.O_RDWR)
try:
    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    child0 = run_flea(state0, config0, '{"view":"grid"}', {})
    try:
        wait_lock_held(child0.pid, lock0, 10)
        assert child0.poll() is None, "child exited while the lock was held, so the wait proves nothing"
        left0 = sorted(p.name for p in (state0 / "flea").iterdir())
        assert left0 == ["ui.json", "ui.json.lock"], f"temp exists before the kill: {left0}"
        child0.kill()
        try:
            child0.wait(timeout=REAP_TIMEOUT)
        except subprocess.TimeoutExpired:
            child0.kill()
            raise AssertionError("before-temp child did not reap")
        assert child0.returncode == -9, f"before-temp child rc={child0.returncode}"
        assert read_bytes(state0 / "flea" / "ui.json") == before0, "kill before the temp moved ui.json"
        assert (state0 / "flea" / "ui.json").stat().st_ino == before0_ino, "kill before the temp replaced inode"
        left0 = sorted(p.name for p in (state0 / "flea").iterdir())
        assert left0 == ["ui.json", "ui.json.lock"], f"kill before the temp left litter: {left0}"
        print(f"ok   stage before-temp kill kept {len(before0)} bytes with no temp", flush=True)
    finally:
        if child0.poll() is None:
            child0.kill()
            child0.wait(timeout=REAP_TIMEOUT)
        try:
            child0.stdout.close()
        except Exception:
            pass
        try:
            child0.stderr.close()
        except Exception:
            pass
finally:
    os.close(lock_fd)

# Killed proof holds the owned tmp inside its first write, then SIGKILLs.
case = root / "killed"
state = case / "state"
config = case / "config"
(state / "flea").mkdir(parents=True)
(config).mkdir(parents=True)
run_once(state, config, '{"view":"list"}', "killed seed")
before = read_bytes(state / "flea" / "ui.json")
before_ino = (state / "flea" / "ui.json").stat().st_ino
entered = case / "entered"
release = case / "release"
if entered.exists():
    entered.unlink()
if release.exists():
    release.unlink()
child = run_flea(state, config, '{"view":"grid"}', {
    "LD_PRELOAD": str(library),
    "FLEA_TEST_UIS_ENTERED": str(entered),
    "FLEA_TEST_UIS_RELEASE": str(release),
})
try:
    wait_path(entered, 10, "barrier receipt")
    receipt = entered.read_text().strip()
    print(f"deterministic receipt {receipt}", flush=True)
    # Sample input: receipt line `12345 7 /run/…/flea/ui.json.12345.tmp`.
    parts = receipt.split(" ", 2)
    assert len(parts) == 3, f"receipt shape: {receipt!r}"
    assert parts[0] == str(child.pid), f"receipt pid {parts[0]} != child {child.pid}"
    tmp_path = Path(parts[2])
    assert tmp_path.is_absolute() and tmp_path.is_relative_to(root), f"tmp outside root: {parts[2]}"
    allow_direct = os.environ.get("FLEA_TEST_UIS_ALLOW_DIRECT") == "1"
    if allow_direct:
        assert parts[2].endswith(f"ui.json.{child.pid}.tmp") or parts[2].endswith("/ui.json"), receipt
    else:
        assert parts[2].endswith(f"ui.json.{child.pid}.tmp"), receipt
    assert tmp_path.is_file(), f"tmp missing: {tmp_path}"
    size = tmp_path.stat().st_size
    assert size > 0, "temp is empty, so the kill proves nothing"
    assert size < len(expected), f"temp size {size} not incomplete vs {len(expected)}"
    live = read_bytes(state / "flea" / "ui.json")
    assert live == before, "ui.json moved before the kill"
    child.kill()
    try:
        child.wait(timeout=REAP_TIMEOUT)
    except subprocess.TimeoutExpired:
        child.kill()
        raise AssertionError("killed child did not reap")
    assert child.returncode == -9, f"killed child rc={child.returncode}"
    after_kill = read_bytes(state / "flea" / "ui.json")
    assert after_kill == before, f"interrupted publication left partial: {after_kill[:200]!r}"
    assert (state / "flea" / "ui.json").stat().st_ino == before_ino, "kill replaced inode"
    left = sorted(p.name for p in (state / "flea").iterdir())
    assert set(left) == {"ui.json", "ui.json.lock", tmp_path.name}, f"kill left more than the owned temp: {left}"
    print(f"ok   deterministic interrupted publication kept {len(before)} bytes, tmp {size} bytes", flush=True)
finally:
    if child.poll() is None:
        child.kill()
        child.wait(timeout=REAP_TIMEOUT)
    try:
        child.stdout.close()
    except Exception:
        pass
    try:
        child.stderr.close()
    except Exception:
        pass

# Stage after the rename: the barrier holds past the publication rename, then SIGKILLs.
case3 = root / "after"
state3 = case3 / "state"
config3 = case3 / "config"
(state3 / "flea").mkdir(parents=True)
config3.mkdir(parents=True)
run_once(state3, config3, '{"view":"list"}', "after seed")
before3 = read_bytes(state3 / "flea" / "ui.json")
before3_ino = (state3 / "flea" / "ui.json").stat().st_ino
entered3 = case3 / "entered"
release3 = case3 / "release"
if entered3.exists():
    entered3.unlink()
if release3.exists():
    release3.unlink()
child3 = run_flea(state3, config3, '{"view":"grid"}', {
    "LD_PRELOAD": str(library),
    "FLEA_TEST_UIS_RENAME_ENTERED": str(entered3),
    "FLEA_TEST_UIS_RENAME_RELEASE": str(release3),
})
try:
    wait_path(entered3, 10, "rename barrier receipt")
    receipt3 = entered3.read_text().strip()
    print(f"rename receipt {receipt3}", flush=True)
    # Sample input: receipt line `12345 rename /run/.../flea/ui.json`.
    parts3 = receipt3.split(" ", 2)
    assert len(parts3) == 3, f"receipt shape: {receipt3!r}"
    assert parts3[0] == str(child3.pid), f"receipt pid {parts3[0]} != child {child3.pid}"
    assert parts3[1] == "rename", f"receipt kind: {receipt3!r}"
    assert parts3[2].endswith("/ui.json"), receipt3
    assert Path(parts3[2]).is_relative_to(root), f"renamed path outside root: {parts3[2]}"
    assert child3.poll() is None, "child exited past the rename, so the hold proves nothing"
    landed = read_bytes(state3 / "flea" / "ui.json")
    assert landed == expected, f"renamed bytes differ before the kill: {landed[:200]!r}"
    assert (state3 / "flea" / "ui.json").stat().st_ino != before3_ino, "rename did not replace inode"
    left3 = sorted(p.name for p in (state3 / "flea").iterdir())
    assert left3 == ["ui.json", "ui.json.lock"], f"rename left a temp behind: {left3}"
    child3.kill()
    try:
        child3.wait(timeout=REAP_TIMEOUT)
    except subprocess.TimeoutExpired:
        child3.kill()
        raise AssertionError("after-rename child did not reap")
    assert child3.returncode == -9, f"after-rename child rc={child3.returncode}"
    assert read_bytes(state3 / "flea" / "ui.json") == expected, "kill past the rename moved ui.json"
    print(f"ok   stage after-rename kill kept {len(expected)} bytes past the rename", flush=True)
finally:
    if child3.poll() is None:
        child3.kill()
        child3.wait(timeout=REAP_TIMEOUT)
    try:
        child3.stdout.close()
    except Exception:
        pass
    try:
        child3.stderr.close()
    except Exception:
        pass

# Released control holds first with release absent, then releases to the exact expected state.
case2 = root / "released"
state2 = case2 / "state"
config2 = case2 / "config"
(state2 / "flea").mkdir(parents=True)
config2.mkdir(parents=True)
run_once(state2, config2, '{"view":"list"}', "released seed")
seed2 = read_bytes(state2 / "flea" / "ui.json")
seed2_ino = (state2 / "flea" / "ui.json").stat().st_ino
entered2 = case2 / "entered"
release2 = case2 / "release"
if entered2.exists():
    entered2.unlink()
if release2.exists():
    release2.unlink()
child2 = run_flea(state2, config2, '{"view":"grid"}', {
    "LD_PRELOAD": str(library),
    "FLEA_TEST_UIS_ENTERED": str(entered2),
    "FLEA_TEST_UIS_RELEASE": str(release2),
})
try:
    wait_path(entered2, 10, "released barrier receipt")
    receipt2 = entered2.read_text().strip()
    print(f"released receipt {receipt2}", flush=True)
    # Sample input: receipt line `12345 7 /run/…/flea/ui.json.12345.tmp`.
    parts2 = receipt2.split(" ", 2)
    assert len(parts2) == 3, f"receipt shape: {receipt2!r}"
    assert parts2[0] == str(child2.pid), f"receipt pid {parts2[0]} != child {child2.pid}"
    tmp2 = Path(parts2[2])
    assert tmp2.is_absolute() and tmp2.is_relative_to(root), f"tmp outside root: {parts2[2]}"
    if os.environ.get("FLEA_TEST_UIS_ALLOW_DIRECT") == "1":
        assert parts2[2].endswith(f"ui.json.{child2.pid}.tmp") or parts2[2].endswith("/ui.json"), receipt2
    else:
        assert parts2[2].endswith(f"ui.json.{child2.pid}.tmp"), receipt2
    assert tmp2.is_file(), f"tmp missing: {tmp2}"
    size2 = tmp2.stat().st_size
    assert size2 > 0 and size2 < len(expected), f"held tmp size {size2} not a partial prefix"
    assert read_bytes(state2 / "flea" / "ui.json") == seed2, "published bytes moved during hold"
    assert (state2 / "flea" / "ui.json").stat().st_ino == seed2_ino, "hold replaced inode"
    assert child2.poll() is None, "child exited before release, so the hold proves nothing"
    release2.touch()
    out2, err2 = child2.communicate(timeout=15)
    assert child2.returncode == 0, f"released run failed: {child2.returncode} {err2}"
    assert entered2.is_file(), "released barrier never intercepted, so the control proves nothing"
    got = read_bytes(state2 / "flea" / "ui.json")
    assert got == expected, f"released state differs: {got[:200]!r} vs {expected[:200]!r}"
    assert (state2 / "flea" / "ui.json").stat().st_ino != seed2_ino, "released write did not replace inode"
    left = list((state2 / "flea").glob("ui.json.*.tmp"))
    assert left == [], f"released temp survives: {left}"
    print(f"ok   released barrier published {len(got)} bytes with new inode", flush=True)
finally:
    if child2.poll() is None:
        child2.kill()
        child2.wait(timeout=REAP_TIMEOUT)

print("deterministic ui-state proof: 4 checks passed", flush=True)
