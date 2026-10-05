#!/usr/bin/env bash
# The persistent SVG cache through the real helper: a repeat answers from disk with no helper, and no other theme or advance is served it.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo "figure-store.sh: qs is not installed"; exit 1; }
resolve_qjs() {
    if [ -n "${FLEA_QJS:-}" ] && [ "${FLEA_QJS#/}" != "${FLEA_QJS}" ] && [ -x "${FLEA_QJS}" ]; then
        printf '%s\n' "${FLEA_QJS}"
    elif [ -x /usr/bin/qjs ]; then
        printf '%s\n' /usr/bin/qjs
    elif [ -x "$PWD/.superpowers/tools/qjs" ]; then
        printf '%s\n' "$PWD/.superpowers/tools/qjs"
    else
        return 1
    fi
}
qjs=$(resolve_qjs) || { echo "figure-store.sh: no qjs (FLEA_QJS, /usr/bin/qjs)"; exit 1; }
fleabin="$PWD/target/debug/flea"
[ -x "$fleabin" ] || { echo "figure-store.sh: no debug binary at $fleabin, run cargo build first"; exit 1; }
export FLEA_UI="$PWD/ui"
# The SVG cache is what is under test, so the bytecode cache and its background build stay off.
export FLEA_FIGURE_CACHE=svg

test_root="$FIXTURE_ROOT/flea-figure-store-$$"
sandbox_make "$test_root"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/figure-store.qml "$test_root/config/shell.qml" || exit 1

# The jail the helper runs in needs user namespaces; a box without them cannot draw a figure, and says so.
probe=$(printf '%s\n' '{"id":1,"kind":"math","source":"x","display":false,"theme":{"bg":"#101315","fg":"#c0caf5"}}' | FLEA_QJS="$qjs" "$fleabin" --figure-helper 2>&1)
if ! printf '%s\n' "$probe" | grep -q '"svg"'; then
    if printf '%s\n' "$probe" | grep -q '^bwrap: No permissions to create new namespace'; then
        echo "figure-store.sh: SKIP no user namespaces in this container, so no jailed helper to draw with"
        exit 0
    fi
    printf 'figure-store.sh: FAIL the helper did not answer: %s\n' "$probe"
    exit 1
fi

output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$fleabin" FLEA_QJS="$qjs" FLEA_UI="$FLEA_UI" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
printf '%s\n' "$output" | grep -aoE 'FIGURE_STORE .*'
# Sample input: FIGURE_STORE 10 checks, 0 failed.
expected=11
if ! printf '%s\n' "$output" | grep -qE "FIGURE_STORE $expected checks, 0 failed$"; then
    printf 'figure-store.sh: FAIL expected %s checks, 0 failed\n' "$expected"
    printf '%s\n' "$output" | grep -aE 'ERROR|TypeError|ReferenceError|flea:' | head -10
    exit 1
fi
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|invalid nullptr parameter' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'figure-store.sh: FAIL the harness logged a warning\n%s\n' "$warnings" | head -10
    exit 1
fi
echo "figure-store: $expected check(s), 0 failed"
