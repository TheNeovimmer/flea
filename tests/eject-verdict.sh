#!/bin/bash
# The hung-chain deadline verdict joins the replacement rule, so the next chain's safe sentence
# retires the stale error instead of hiding behind it (fs5 slow legs). Read-only, no display.
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0
pins=0
check() {
  local label="$1" expected="$2" actual="$3"
  pins=$((pins + 1))
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label: expected $expected, got $actual"
    fail=1
  fi
}

# The deadline block is the Timer body, so a _lastVerdict elsewhere cannot satisfy this.
deadline=$(awk '/id: powerOffTimeout/,/^    \}/' ui/DeviceMounts.qml)
check "deadline records its sentence as the last verdict" 1 "$(printf '%s\n' "$deadline" | grep -c '_lastVerdict = text')"
check "deadline forgets the verdict it replaces" 1 "$(printf '%s\n' "$deadline" | grep -c 'forgetMessage(root._lastVerdict)')"
check "both verdict writers replace the last one" 2 "$(grep -c 'forgetMessage(root._lastVerdict)' ui/DeviceMounts.qml)"
check "the chain state answers through one function" 1 "$(grep -c 'function ejectState()' ui/DeviceMounts.qml)"
check "the rail exposes the chain state fresh at ipc time" 1 "$(grep -c 'function ejectChainState()' ui/Sidebar.qml)"
check "ipc names the chain state beside the rail" 1 "$(grep -c 'function deviceEjectState()' ui/Ipc.qml)"
check "slow legs diagnose a failure with rail and chain" 1 "$(grep -c 'deviceEjectState' tests/ui.sh)"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf 'EJECTVERDICT PASS pins=%s\n' "$pins"
