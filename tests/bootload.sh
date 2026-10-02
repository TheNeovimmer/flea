#!/usr/bin/env bash
# xw6r3: every file under ui/boot/ loads the way the shell loads it, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "bootload.sh: qs is not installed, cannot load the boot entries"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-bootload.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe reaches the shipped boot files through this link, so it loads what the shell loads.
ln -s "$PWD/ui/boot" "$test_root/config/boot" || exit 1
cp tests/bootload.qml "$test_root/config/shell.qml" || exit 1

# Entries carry ShellRoot and compile only; the rest instantiate with no props, pre-onLoaded.
files=$(cd ui/boot && printf '%s ' *.qml | sort)
entries=""
for f in $files; do grep -q 'ShellRoot *{' "ui/boot/$f" && entries="$entries $f"; done
expected=$(cd ui/boot && printf '%s\n' *.qml | wc -l)

# A declarative Loader source carries no initial props, so a root-level required prop on a
# Loader-loaded file can never hold at creation; delegate props nested deeper are untouched.
required=""
for f in $files; do
    case "$entries" in *" $f"*) continue ;; esac
    hit=$(grep -n '^    required property' "ui/boot/$f" || true)
    [ -n "$hit" ] && required="$required ui/boot/$f:$hit"
done
if [ -n "$required" ]; then
    printf 'FAIL a Loader-loaded boot file declares a root-level required property:\n'
    printf '%s\n' "$required" | sed 's/^/     /'
    exit 1
fi

# Keys on a PanelWindow warns at runtime, PanelWindow is not an Item, so the
# handler never fires. Offscreen has no PanelWindow backend, so the load
# cannot see it; this static check fails the class instead.
keys_bad=""
for f in $files; do
    if grep -q 'PanelWindow' "ui/boot/$f" && grep -q 'Keys\.on' "ui/boot/$f"; then
        grep -q 'focus: true' "ui/boot/$f" || keys_bad="$keys_bad ui/boot/$f"
    fi
done
if [ -n "$keys_bad" ]; then
    printf 'FAIL a boot file attaches Keys to a PanelWindow, move it onto a focused Item:\n'
    printf '%s\n' "$keys_bad" | sed 's/^/     /'
    exit 1
fi

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BOOTLOAD_FILES="$files" FLEA_BOOTLOAD_ENTRIES="$entries" \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, the probe's own evidence: "  INFO qml: BOOTLOAD PASS files=4".
pass_count=$(printf '%s\n' "$output" | grep -c "BOOTLOAD PASS files=$expected")
fail_count=$(printf '%s\n' "$output" | grep -c 'BOOTLOAD FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a boot entry does not load the way the shell loads it\n'
    printf '%s\n' "$output" | grep -a 'BOOTLOAD'
    printf '%s\n' "$output" | grep -aiE 'is not a type|Required property|Failed to load|Cannot assign' | head -10
    exit 1
fi
# Backstop: a load warning the probe never converted still fails the gate.
warn_count=$(printf '%s\n' "$output" | grep -aciE 'is not a type|Required property .* was not initialized')
if [ "$warn_count" -ne 0 ]; then
    printf 'FAIL the log carries a load warning beside the passing probe\n'
    printf '%s\n' "$output" | grep -aiE 'is not a type|Required property .* was not initialized' | head -10
    exit 1
fi
# A note is an offscreen-only failure the probe could not classify; only the pinned
# PanelWindow artifact may pass, every novel one fails beside the probe's own FAIL.
notes=$(printf '%s\n' "$output" | grep -a 'BOOTLOAD NOTE' || true)
if [ -n "$notes" ]; then
    other=$(printf '%s\n' "$notes" | grep -av 'No PanelWindow backend loaded' || true)
    if [ -n "$other" ]; then
        printf 'FAIL a boot entry failed to instantiate for an unclassified reason\n'
        printf '%s\n' "$other" | head -5
        exit 1
    fi
fi
printf '%s\n' "$output" | grep -o "BOOTLOAD PASS files=$expected"
