#!/usr/bin/env bash
# tp1 touchpad plus tp2 elastic edges: fake wheels and an injected clock drive FastScrollHandler on a real ui/List.qml over 3000 rows, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "touchpad.sh: qs is not installed, cannot drive the scroll probe"
    exit 1
fi

# The uinput struct check needs no device, so it runs wherever the scroll probe runs.
python3 "$PWD/tools/flea-touchpad" check || exit 1

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-touchpad.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/touchpad.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input: "\e[34m DEBUG\e[97m qml\e[0m: TOUCHPAD PASS stroke=1200 lift=90 rest=4182 tail=2982.3 objs=580 delegates=26 edgeTop=-42.5 edgeBottom=77765.5 tailPeak=77823.0"
pass_count=$(printf '%s\n' "$output" | grep -c 'TOUCHPAD PASS')
edge_count=$(printf '%s\n' "$output" | grep -c 'TOUCHPAD EDGE PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'TOUCHPAD FAIL')
if [ "$pass_count" -ne 1 ] || [ "$edge_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a touchpad stroke, tail, stop, share, cost or edge check went red\n'
    printf '%s\n' "$output" | grep -a 'TOUCHPAD'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'TOUCHPAD PASS.*'
printf '%s\n' "$output" | grep -o 'TOUCHPAD EDGE PASS.*'
