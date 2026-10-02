#!/bin/bash
# The hung-chain deadline verdict joins the replacement rule, so the next safe sentence retires the stale error.
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
# Sample input, Timer block: "        id: powerOffTimeout" to "    }".
deadline=$(awk '/id: powerOffTimeout/,/^    \}/' ui/DeviceMounts.qml)
check "deadline records its sentence as the last verdict" 1 "$(printf '%s\n' "$deadline" | grep -c '_lastVerdict = text')"
check "deadline forgets the verdict it replaces" 1 "$(printf '%s\n' "$deadline" | grep -c 'forgetMessage(root._lastVerdict)')"
forget_at=$(printf '%s\n' "$deadline" | grep -n 'forgetMessage(root._lastVerdict)' | cut -d: -f1)
assign_at=$(printf '%s\n' "$deadline" | grep -n '_lastVerdict = text' | cut -d: -f1)
message_at=$(printf '%s\n' "$deadline" | grep -n 'root.message(text' | cut -d: -f1)
forget_first=0
message_last=0
if [ "$forget_at" -lt "$assign_at" ]
then
  forget_first=1
fi
if [ "$assign_at" -lt "$message_at" ]
then
  message_last=1
fi
check "deadline forgets the old verdict before recording the new one" 1 "$forget_first"
check "deadline posts the new verdict after recording it" 1 "$message_last"
check "both verdict writers replace the last one" 2 "$(grep -c 'forgetMessage(root._lastVerdict)' ui/DeviceMounts.qml)"
check "the chain state answers through one function" 1 "$(grep -c 'function ejectState()' ui/DeviceMounts.qml)"
check "the rail exposes the chain state fresh at ipc time" 1 "$(grep -c 'function ejectChainState()' ui/Sidebar.qml)"
check "ipc names the chain state beside the rail" 1 "$(grep -c 'function deviceEjectState()' ui/Ipc.qml)"
check "slow legs diagnose a failure with rail and chain" 1 "$(grep -c 'deviceEjectState' tests/ui.sh)"

if [ "$fail" -ne 0 ]; then
  exit 1
fi
printf 'EJECTVERDICT PASS pins=%s\n' "$pins"
