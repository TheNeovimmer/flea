#!/usr/bin/env bash
# Settings hints, the ruler, hint bands and caption baselines against the boards at size 14, offscreen with no compositor, so no display or display lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "settings-columns.sh: qs is not installed, cannot draw a settings row"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-settings-columns-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
# The boards draw JetBrains Mono, which fc-match monospace is on the install box and is not in every image, so the probe pins it.
BOARD_FONT="JetBrainsMono Nerd Font"
cat > "$test_root/fonts.conf" <<CONF || exit 1
<?xml version="1.0"?>
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <match target="pattern">
    <test name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>$BOARD_FONT</string></edit>
  </match>
</fontconfig>
CONF
# Sample input, one line: "JetBrainsMono Nerd Font,JetBrainsMono NF"; the pinned face must lead what monospace resolves to.
resolved=$(FONTCONFIG_FILE="$test_root/fonts.conf" fc-match -f '%{family}' monospace 2>&1)
case $resolved in
    "$BOARD_FONT" | "$BOARD_FONT",*) ;;
    *) printf 'FAIL fonts.conf: monospace resolves to "%s", the boards draw "%s", so every metric would be another font\n' "$resolved" "$BOARD_FONT"; exit 1 ;;
esac
cp tests/settings-columns.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FONTCONFIG_FILE="$test_root/fonts.conf" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: SETTINGS_COLUMNS PASS label=41.85 labels=101 hints=10 rulers=1 footer=14"
pass_count=$(printf '%s\n' "$output" | grep -c 'SETTINGS_COLUMNS PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'SETTINGS_COLUMNS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a settings hint or ruler left the label column\n'
    printf '%s\n' "$output" | grep -aE 'SETTINGS_COLUMNS|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'SETTINGS_COLUMNS PASS.*'
