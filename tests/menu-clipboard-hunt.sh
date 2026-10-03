#!/usr/bin/env bash
# Real browser window and backend, with a deterministic system clipboard-helper double.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
python3 tests/menu-clipboard-checks-test.py || exit 1
command -v qs >/dev/null || { echo 'FAIL qs is unavailable'; exit 1; }
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-menu-clipboard-hunt.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{home,state,data,cache,runtime,config,bin,source,copy-dest,cut-dest,paste-dest,pasteas-dest,pasteas-absolute-dest,pasteas-hard-dest,original-dest} || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/menu-clipboard-hunt.qml "$test_root/config/shell.qml" || exit 1
printf 'alpha contents\n' > "$test_root/source/alpha.txt"
printf 'beta contents\n' > "$test_root/source/beta.txt"
for link_dest in pasteas pasteas-absolute pasteas-hard; do
    printf 'canary contents\n' > "$test_root/$link_dest-dest/canary.txt"
done
ln -s ../source/alpha.txt "$test_root/original-dest/file-link" || exit 1
ln -s / "$test_root/original-dest/root-link" || exit 1
# Deterministic versions of the existing clipboard helpers, no compositor or foreign clipboard.
cat > "$test_root/bin/wl-copy" <<'PY'
#!/usr/bin/env python3
import json, os, sys
path = os.environ["FLEA_HUNT_CLIPBOARD"]
text = sys.stdin.read()
with open(path, "w") as output:
    output.write(text)
with open(path + ".calls", "a") as output:
    output.write(json.dumps({"args": sys.argv[1:], "text": text}) + "\n")
PY
cat > "$test_root/bin/wl-paste" <<'SH'
#!/bin/sh
case " $* " in
    *' --list-types '*) printf 'text/uri-list\nx-special/gnome-copied-files\n' ;;
    *) cat "$FLEA_HUNT_CLIPBOARD" ;;
esac
SH
chmod +x "$test_root/bin/wl-copy" "$test_root/bin/wl-paste" || exit 1
# Intercept terminal launch only; the candidate owns every backend and state request.
cat > "$test_root/bin/flea-hunt" <<'SH'
#!/bin/sh
if [ "${1:-}" = --terminal ]; then
    printf '%s\n' "$2" >> "$FLEA_HUNT_CLIPBOARD.terminals"
    exit 0
fi
exec "$FLEA_HUNT_REAL_BIN" "$@"
SH
chmod +x "$test_root/bin/flea-hunt" || exit 1
failed=0
checks=0
failures=0
for action in copy paste cut copyas-list copyas-grid copyas-columns terminal pasteas pasteas-absolute pasteas-hard original; do
    printf 'alpha contents\n' > "$test_root/source/alpha.txt"
    printf 'beta contents\n' > "$test_root/source/beta.txt"
    start="$test_root/source"
    [ "$action" = paste ] && start="$test_root/paste-dest"
    [ "$action" = original ] && start="$test_root/original-dest"
    dest="$test_root/$action-dest"
    [ "$action" = terminal ] && dest="$test_root/copy-dest"
    # Fresh-window Paste consumes Copy's publication without replacing it with fixture paths.
    if [[ "$action" == copy || "$action" == cut ]]; then
        : > "$test_root/clipboard"
    elif [[ "$action" != paste ]]; then
        printf 'file://%s/source/alpha.txt\nfile://%s/source/beta.txt\n' "$test_root" "$test_root" > "$test_root/clipboard"
    fi
    : > "$test_root/clipboard.calls"
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/config" \
        XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" XDG_RUNTIME_DIR="$test_root/runtime" \
        PATH="$test_root/bin:$PATH" FLEA_BIN="$test_root/bin/flea-hunt" FLEA_HUNT_REAL_BIN="$PWD/target/debug/flea" FLEA_PATH="$start" \
        FLEA_HUNT_ACTION="$action" FLEA_HUNT_DEST="$dest" FLEA_HUNT_CLIPBOARD="$test_root/clipboard" \
        FLEA_HUNT_SOURCE="$test_root/source" FLEA_HUNT_CHECKS="$PWD/tests/menu-clipboard-checks.py" \
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 qs -p "$test_root/config" 2>&1)
    code=$?
    printf '%s\n' "$output" | grep -a 'CLIPHUNT'
    probe_checks=$(printf '%s\n' "$output" | grep -acE 'CLIPHUNT (PASS|FAIL)' || true)
    probe_failures=$(printf '%s\n' "$output" | grep -ac 'CLIPHUNT FAIL' || true)
    checks=$((checks + probe_checks + 1))
    failures=$((failures + probe_failures))
    if [ "$code" -ne 143 ] || ! printf '%s\n' "$output" | grep -aq "CLIPHUNT DONE action=$action"; then
        printf 'FAIL %s probe did not complete: exit=%s\n' "$action" "$code"
        printf '%s\n' "$output" | tail -12
        failed=1
        failures=$((failures + 1))
    fi
    if [[ "$action" == copy || "$action" == cut ]]; then
        checks=$((checks + 1))
        if ! python3 tests/menu-clipboard-checks.py publication "$action" "$test_root/clipboard.calls" "$test_root/source"; then
            failed=1
            failures=$((failures + 1))
        fi
    fi
    if printf '%s\n' "$output" | grep -aq 'CLIPHUNT FAIL'; then failed=1; fi
    if [[ "$action" == copyas-* ]]; then
        checks=$((checks + 1))
        # Sample input: {"text":"/source/alpha.txt\n/source/beta.txt"} is one Copy as publication.
        python3 - "$test_root/clipboard.calls" "$test_root/source" <<'PY'
import json, pathlib, sys
calls = [json.loads(line)["text"] for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
root = sys.argv[2]
paths = [root + "/alpha.txt", root + "/beta.txt"]
expected = ["\n".join(paths), "alpha.txt\nbeta.txt", "alpha\nbeta", root + "\n" + root,
            "\n".join(pathlib.Path(p).as_uri() for p in paths),
            "\n".join("'" + p + "'" for p in paths), "\n".join(paths)]
if calls != expected:
    print("FAIL Copy as leaves or Ctrl+Shift+C did not copy the whole selection:", repr(calls))
    sys.exit(1)
print("PASS six Copy as leaves and Ctrl+Shift+C copied both selected files")
PY
        if [ "$?" -ne 0 ]; then failed=1; failures=$((failures + 1)); fi
    elif [[ "$action" != terminal && "$action" != original ]]; then
        for file in alpha.txt beta.txt; do
            checks=$((checks + 1))
            if [ ! -f "$test_root/$action-dest/$file" ]; then
                printf 'FAIL %s destination lacks %s\n' "$action" "$file"
                failed=1
                failures=$((failures + 1))
            fi
        done
        if [[ "$action" == cut || "$action" == pasteas* ]]; then
            checks=$((checks + 1))
            if ! python3 tests/menu-clipboard-checks.py files "$action" "$test_root/source" "$dest"; then
                failed=1
                failures=$((failures + 1))
            fi
        fi
    fi
    # Offscreen cannot set window masks; every other runtime error is significant.
    warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' \
        | grep -vF 'This plugin does not support setting window masks' || true)
    checks=$((checks + 1))
    if [ -n "$warnings" ]; then
        printf 'FAIL %s runtime warnings\n%s\n' "$action" "$warnings"
        failed=1
        failures=$((failures + 1))
    fi
done
printf 'menu-clipboard-hunt: %s checks, %s failed\n' "$checks" "$failures"
[ "$failed" -eq 0 ]
