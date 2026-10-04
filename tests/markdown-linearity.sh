#!/usr/bin/env bash
# Gate deterministic parser work at 64 KiB and 512 KiB; milliseconds are diagnostics only.
set -uo pipefail
script_path=$(readlink -f -- "$0") || exit 1
cd "$(dirname "$0")/.." || exit 1

# Verify wrapper rejection with partial timeout, missing samples, malformed records and excessive work.
if [ "${1:-}" != "--probe" ]; then
    probe_root=$(mktemp -d "${TMPDIR:-/tmp}/markdown-linearity.XXXXXX") || exit 1
    trap 'rm -rf -- "$probe_root"' EXIT
    cat > "$probe_root/timeout" <<'STUB'
#!/usr/bin/env bash
if [ "$LINEARITY_CASE" = timeout ]; then
    echo 'qml: WORK codeDense 1 8 1 8'
    exit 124
fi
if [ "$LINEARITY_CASE" = empty ]; then
    exit 0
fi
if [ "$LINEARITY_CASE" = qml-error ]; then
    echo 'qml: WORK codeDense 1 8 1 8'
    exit 1
fi
sample=0
[ ! -f "$LINEARITY_COUNTER" ] || read -r sample < "$LINEARITY_COUNTER"
sample=$((sample + 1))
echo "$sample" > "$LINEARITY_COUNTER"
for name in codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun tagCost tagAttrs linkFrames blankList blankIndent punctTail; do
    [ "$LINEARITY_CASE" != missing ] || [ "$name" != listDeep ] || continue
    [ "$LINEARITY_CASE" != short ] || [ "$sample" != 2 ] || [ "$name" != listDeep ] || continue
    large=8
    [ "$LINEARITY_CASE" != nonlinear ] || large=13
    [ "$LINEARITY_CASE" != zero ] || large=0
    if [ "$LINEARITY_CASE" = duplicate ]; then
        printf 'qml: WORK %s 1 %s 1 999\n' "$name" "$large"
    fi
    if [ "$LINEARITY_CASE" = fields ]; then
        printf 'qml: WORK %s 1 %s 1 999 extra\n' "$name" "$large"
    elif [ "$LINEARITY_CASE" = unknown ]; then
        printf 'qml: WORK bogus 1 %s 1 999\n' "$large"
    else
        printf 'qml: WORK %s 1 %s 1 999\n' "$name" "$large"
    fi
done
STUB
    chmod +x "$probe_root/timeout"
    for probe in timeout qml-error empty missing short nonlinear duplicate fields zero unknown diagnostics; do
        rm -f "$probe_root/counter"
        if env PATH="$probe_root:$PATH" LINEARITY_CASE="$probe" LINEARITY_COUNTER="$probe_root/counter" \
            bash "$script_path" --probe > "$probe_root/output" 2>&1; then
            status=0
        else
            status=$?
        fi
        expected_status=1
        case "$probe" in
            timeout|qml-error) expected_message='FAIL parser harness never finished (run 1)' ;;
            empty) expected_message='FAIL missing sample codeDense in run 1' ;;
            missing) expected_message='FAIL missing sample listDeep in run 1' ;;
            short) expected_message='FAIL missing sample listDeep in run 2' ;;
            nonlinear) expected_message='FAIL codeDense work ratio 13/1 exceeds 12' ;;
            duplicate|fields) expected_message='FAIL invalid work sample in run 1: codeDense' ;;
            zero) expected_message='FAIL zero work sample in run 1: codeDense' ;;
            unknown) expected_message='FAIL invalid work sample in run 1: bogus' ;;
            diagnostics)
                expected_status=0
                expected_message='PASS 15 pathological inputs, 3 complete repetitions'
                ;;
        esac
        if [ "$status" -ne "$expected_status" ] || ! grep -qF "$expected_message" "$probe_root/output"; then
            echo "FAIL wrapper regression $probe status=$status"
            cat "$probe_root/output"
            exit 1
        fi
        echo "ok wrapper regression $probe status=$status"
    done
fi

if ! command -v qml6 >/dev/null; then
    echo "FAIL qml6 is not installed"
    exit 1
fi

if [ "${1:-}" != "--probe" ]; then
    # Import the shipped text component without Quickshell's Theme dependency in the marker-column probe.
    text_module="$probe_root/markdown-text"
    mkdir -p "$text_module" || exit 1
    mkdir -p "$text_module/js" || exit 1
    cp ui/MarkdownText.qml ui/MarkdownList.qml "$text_module/" || exit 1
    cp ui/js/MarkdownLists.js "$text_module/js/" || exit 1
    printf 'MarkdownText 1.0 MarkdownText.qml\nMarkdownList 1.0 MarkdownList.qml\nsingleton Theme 1.0 Theme.qml\n' > "$text_module/qmldir" || exit 1
    cat > "$text_module/Theme.qml" <<'THEME'
pragma Singleton
import QtQuick
QtObject {
    property var color: ({ foreground: "#ffffff" })
    property var font: ({ family: "sans-serif", body: 16 })
    property var spacing: ({ gap: 8 })
}
THEME
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 30 qml6 tests/markdown-preview-state.qml -- "$text_module" || exit 1
    # The end-follow over a real lazy list needs no Theme, so it takes no module.
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 30 qml6 tests/markdown-endhold.qml || exit 1
fi

run_once() {
    local output status
    # Check qml6 or timeout directly before extracting complete work records.
    output=$(TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 280 qml6 tests/markdown-linearity.qml -- ui/js/Md*.js 2>&1)
    status=$?
    if [ "$status" != 0 ]; then
        printf '%s\n' "$output" | head -12 >&2
        return "$status"
    fi
    printf '%s\n' "$output" | sed -n 's/^qml: WORK //p'
}

expected=(codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun tagCost tagAttrs linkFrames blankList blankIndent punctTail)
repetitions=3
size_ratio=8
margin_numerator=3
margin_denominator=2
work_limit=$((size_ratio * margin_numerator / margin_denominator))
max_integer_digits=18
for ((run=1; run<=repetitions; run++)); do
    result=$(run_once) || { echo "FAIL parser harness never finished (run $run)"; exit 1; }
    declare -A wanted=() seen=()
    for name in "${expected[@]}"; do
        wanted[$name]=1
    done
    failed=0
    # Sample input: codeDense 1200 9600 1 8 (work at each size, then diagnostic milliseconds).
    while read -r name work_a work_b ms_a ms_b extra; do
        if [[ -z "$name" || ! -v "wanted[$name]" ]]; then
            echo "FAIL invalid work sample in run $run: $name $work_a $work_b $ms_a $ms_b $extra"
            failed=1
            continue
        fi
        seen[$name]=$((${seen[$name]:-0} + 1))
        if [[ ${seen[$name]} != 1 || -n "$extra" || -z "$ms_a" || -z "$ms_b"
            || ! "$work_a" =~ ^[0-9]+$ || ! "$work_b" =~ ^[0-9]+$
            || ${#work_a} -gt $max_integer_digits || ${#work_b} -gt $max_integer_digits ]]; then
            echo "FAIL invalid work sample in run $run: $name $work_a $work_b $ms_a $ms_b $extra"
            failed=1
            continue
        fi
        work_a=$((10#$work_a))
        work_b=$((10#$work_b))
        if ((work_a == 0 || work_b == 0)); then
            echo "FAIL zero work sample in run $run: $name"
            failed=1
        elif ((work_b / work_a > work_limit || (work_b / work_a == work_limit && work_b % work_a > 0))); then
            echo "FAIL $name work ratio $work_b/$work_a exceeds $work_limit"
            failed=1
        else
            echo "ok $name work=$work_a/$work_b ms=$ms_a/$ms_b run=$run"
        fi
    done <<< "$result"
    for name in "${expected[@]}"; do
        if [[ ${seen[$name]:-0} != 1 ]]; then
            echo "FAIL missing sample $name in run $run"
            failed=1
        fi
    done
    [ "$failed" = 0 ] || exit 1
done
printf 'PASS %s pathological inputs, %s complete repetitions, work bound 8x plus 50%% margin\n' "${#expected[@]}" "$repetitions"
