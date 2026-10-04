#!/usr/bin/env bash
# The real ui/ChromeButton.qml draws its keyboard ring only for the keyboard, 24 x 24 and centred in the hit box; offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "chromering.sh: qs is not installed, cannot draw a button"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-chromering-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/chromering.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: CHROMERING PASS 63 checks"
expected_checks=85
pass_count=$(printf '%s\n' "$output" | grep -c 'CHROMERING PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'CHROMERING FAIL')
ran_checks=$(printf '%s\n' "$output" | grep -ao 'CHROMERING PASS [0-9]* checks' | grep -o '[0-9]*')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ "${ran_checks:-0}" -ne "$expected_checks" ]; then
    printf 'FAIL the chrome button ring broke, or ran %s checks and not %s\n' "${ran_checks:-0}" "$expected_checks"
    printf '%s\n' "$output" | grep -a 'CHROMERING FAIL'
    printf '%s\n' "$output" | grep -aE 'ERROR|error' | grep -av 'CHROMERING' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'CHROMERING PASS.*'
