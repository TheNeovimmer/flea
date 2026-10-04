#!/usr/bin/env bash
# The real ui/PreviewMarkdown.qml over a fixture document, grabbed offscreen and judged on pixel facts: the chrome chip behind inline code, the table's rules without verticals, no Qt default link blue, and the quote bar's muted ink.
set -u
script_path=$(readlink -f -- "$0") || exit 1
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

check_warnings() {
    local output=$1 platform_warning worker_warning maximum_worker_warnings worker_warnings warnings
    # Offscreen window-mask warning is expected; the caller bounds WorkerScript warnings for the active parse path.
    platform_warning='This plugin does not support setting window masks'
    worker_warning='QObject::connect(QJSEngine, QtObject): invalid nullptr parameter'
    maximum_worker_warnings=${2:-1}
    worker_warnings=$(printf '%s\n' "$output" | grep -cF "$worker_warning")
    if [ "$worker_warnings" -gt "$maximum_worker_warnings" ]; then
        printf 'FAIL at most %s WorkerScript warning allowed, got %s\n' "$maximum_worker_warnings" "$worker_warnings"
        return 1
    fi
    warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning" | grep -vF "$worker_warning")
    if [ -n "$warnings" ]; then
        printf 'FAIL the render harness logged a warning\n'
        printf '%s\n' "$warnings" | head -10
        return 1
    fi
}

if [ "${1:-}" = "--check-warnings" ]; then
    check_warnings "$(cat)" "${2:-1}"
    exit $?
fi

warning_control() {
    local name=$1 transcript=$2 expected_status=$3 expected_message=$4 output status
    output=$(printf '%s\n' "$transcript" | bash "$script_path" --check-warnings)
    status=$?
    if [ "$status" -ne "$expected_status" ] || [[ "$output" != *"$expected_message"* ]]; then
        printf 'FAIL warning control %s status=%s: %s\n' "$name" "$status" "$output"
        exit 1
    fi
    printf 'ok warning control %s status=%s\n' "$name" "$status"
}

worker_warning='WARN: QObject::connect(QJSEngine, QtObject): invalid nullptr parameter'
warning_control zero 'MARKDOWN_RENDER PASS chip, rules, bar and links all read' 0 ''
warning_control one "$worker_warning" 0 ''
warning_control two "$(printf '%s\n%s\n' "$worker_warning" "$worker_warning")" 1 'WorkerScript warning'
warning_control other 'WARN: probe unexpected warning' 1 'render harness logged a warning'
if check_warnings "$worker_warning" 0 >/dev/null; then
    echo "FAIL inline parse accepted a WorkerScript warning"; exit 1
fi
check_warnings "" 0 || exit 1
printf 'ok inline parse allows zero WorkerScript warnings\n'

if ! command -v qs >/dev/null; then
    echo "markdown-render.sh: qs is not installed, cannot render the preview"
    exit 1
fi

python3 tests/markdown-gates.py || exit 1

test_root="$FIXTURE_ROOT/flea-markdown-render-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-render.js tests/markdown-bar.js "$test_root/config/" || exit 1
cp tests/markdown-render.qml "$test_root/config/shell.qml" || exit 1

cat > "$test_root/notes.md" <<'EOF'
# Rendered notes

## Second level

A paragraph with `loadFile()` inline code and [a guide](https://example.com/guide).

> A quoted line for the bar.

1. First item
2. Second item

- Alpha item
- Beta item

| Kind | Asks for | Cached |
| :--- | :--- | :--- |
| rows | the cursor | yes |
| facts | the table | yes |

```js
var fenced = true;
```

![shot](https://cdn.example.com/shot.png)
EOF

: > "$test_root/notes.md.empty.md"
printf '# Identical\n' > "$test_root/notes.md.first.md" || exit 1
cp "$test_root/notes.md.first.md" "$test_root/notes.md.second.md" || exit 1
# A name far past any bar width, so the bar must elide it and the room it may take is measured.
long_name_digits=200
long_fixture="$test_root/long-$(printf "%0${long_name_digits}d" 0).md"
cp "$test_root/notes.md" "$long_fixture" || exit 1

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" FLEA_MARKDOWN_LONG="$long_fixture" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict line: "  INFO qml: MARKDOWN_RENDER PASS chip, rules, bar and links all read"
if [ "$(printf '%s\n' "$output" | grep -c 'MARKDOWN_RENDER PASS')" -ne 1 ] || printf '%s\n' "$output" | grep -q 'MARKDOWN_RENDER FAIL'; then
    printf 'FAIL the rendered preview missed a pixel fact\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_RENDER|ERROR|error'
    exit 1
fi
check_warnings "$output" 0 || exit 1
shot=$(ls "$test_root/runtime"/markdown-render-*-base.png 2>/dev/null | head -1)
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ] && [ -n "$shot" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS" || exit 1
    cp "$shot" "$FLEA_CI_SUITE_LOGS/markdown-render.png" || exit 1
    large_shot=$(ls "$test_root/runtime"/markdown-render-*-large.png 2>/dev/null | head -1)
    if [ -z "$large_shot" ]; then
        printf 'FAIL markdown-render: large shot expected %s/runtime/markdown-render-*-large.png; arrived [<missing>]\n' "$test_root" >&2
        exit 1
    fi
    cp "$large_shot" "$FLEA_CI_SUITE_LOGS/markdown-render-large.png" || exit 1
    printf 'shot %s\n' "$FLEA_CI_SUITE_LOGS/markdown-render.png"
elif [ -n "$shot" ]; then
    printf 'shot %s\n' "$shot"
fi
printf '%s\n' "$output" | grep -oE 'MARKDOWN_RENDER (CHECK|body=|PASS).*'

cp tests/markdown-source-render.qml "$test_root/config/shell.qml" || exit 1
source_output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
printf '%s\n' "$source_output" | grep -oE 'MARKDOWN_SOURCE .*'
check_warnings "$source_output" 0 || exit 1
expected_source_checks=15
# Sample input: MARKDOWN_SOURCE 15 checks, 0 failed
if ! printf '%s\n' "$source_output" | grep -qF "MARKDOWN_SOURCE $expected_source_checks checks, 0 failed"; then
    printf 'FAIL markdown-render: Source expected %s checks, 0 failed for %s/notes.md; arrived [%s]\n' "$expected_source_checks" "$test_root" "${source_output:-<empty>}" >&2
    exit 1
fi
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    cp "$test_root/runtime/markdown-source.png" "$FLEA_CI_SUITE_LOGS/markdown-source.png" || exit 1
fi

# The heading ink as ui/Theme.qml derives it, over palettes where each source wins and where none does.
cp tests/markdown-headink.qml "$test_root/config/shell.qml" || exit 1
headink_output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
printf '%s\n' "$headink_output" | grep -oE 'MARKDOWN_HEADINK .*'
check_warnings "$headink_output" 0 || exit 1
expected_headink_checks=9
# Sample input: MARKDOWN_HEADINK 9 checks, 0 failed
if ! printf '%s\n' "$headink_output" | grep -qF "MARKDOWN_HEADINK $expected_headink_checks checks, 0 failed"; then
    printf 'FAIL markdown-render: heading ink expected %s checks, 0 failed; arrived [%s]\n' "$expected_headink_checks" "${headink_output:-<empty>}" >&2
    exit 1
fi
