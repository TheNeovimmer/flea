#!/usr/bin/env bash
# Gate that a block nested in a list item or a quote draws with its top-level recipe, and that an empty heading or quote has no height.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-nest.sh: qs is not installed, cannot render the preview"
    exit 1
fi
fleabin=""
for cand in "$PWD/target/debug/flea" "$PWD/target/release/flea"; do
    if [ -x "$cand" ]; then
        fleabin="$cand"
        break
    fi
done
# The nested formulas ask the real figure helper, which needs quickjs-ng and this checkout's binary.
if [ -n "${FLEA_QJS:-}" ] && [ -x "${FLEA_QJS}" ]; then
    qjs=$FLEA_QJS
elif command -v qjs >/dev/null 2>&1; then
    qjs=$(command -v qjs)
elif [ -x "$PWD/.superpowers/tools/qjs" ]; then
    qjs="$PWD/.superpowers/tools/qjs"
else
    echo 'FAIL missing qjs: the real figure helper requires quickjs-ng'
    exit 1
fi
[ -n "$fleabin" ] || { echo 'FAIL missing flea binary: build this checkout before rendering figures'; exit 1; }

test_root="$FIXTURE_ROOT/flea-markdown-nest-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/docs" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-nest.js "$test_root/config/" || exit 1
cp tests/markdown-nest.qml "$test_root/config/shell.qml" || exit 1

# A fence, an inline formula, a table, a quote and indented code, each inside an item or a quote, with a top-level fence to compare against.
cat > "$test_root/docs/nest.md" <<'MD'
# Nest

```
top
```

- item
  ```js
  var a = 1;
  ```
  tail

> quote
> ```
> code
> ```

- maths $x$ in item

> maths $y$ in quote

> | h | i |
> | - | - |
> | 1 | 2 |

- a
  > inside item

>     indented
MD
printf 'before\n\n#\n\n>\n\nafter\n' > "$test_root/docs/empty.md"
printf 'plain text\n\n# Title\n\nmaths $x$ here\n' > "$test_root/docs/compact.md"

output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_NEST_DIR="$test_root/docs" \
    FLEA_BIN="$fleabin" FLEA_QJS="$qjs" FLEA_UI="$PWD/ui" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
printf '%s\n' "$output" | grep -oE 'MARKDOWN_NEST .*'
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|invalid nullptr parameter' | grep -vF "$platform_warning")
[ -z "$warnings" ] || { printf 'FAIL nesting harness warning: %s\n' "$warnings"; exit 1; }
expected_checks=23 # Sixteen for the nest fixture, three for the empty block rule, four for the second text size.
# Sample input: MARKDOWN_NEST 23 checks, 0 failed
if ! printf '%s\n' "$output" | grep -qE "(^|: )MARKDOWN_NEST $expected_checks checks, 0 failed$"; then
    printf 'FAIL markdown-nest: expected %s checks, 0 failed; arrived [%s]\n' "$expected_checks" "${output:-<empty>}" >&2
    exit 1
fi
echo "PASS nested blocks draw with their top-level recipe"
