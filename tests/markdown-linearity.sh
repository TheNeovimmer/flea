#!/usr/bin/env bash
# Gate deterministic parser work at 64 KiB and 512 KiB; milliseconds are diagnostics only.
set -uo pipefail
script_path=$(readlink -f -- "$0") || exit 1
cd "$(dirname "$0")/.." || exit 1

# The harness run's hang guard grows with how slow a spin of fixed work ran on this box just now, never past a cap; the linearity bound itself is work counts and never moves.
hang_guard_s=280
spin_idle_ms=700
guard_scale_cap=8
spin_iterations=1000000
# Nanoseconds in one millisecond, for the spin calibration below.
ns_per_ms=1000000
scaled_guard_s() {
    local base=$1 cal_ms=$2 idle_ms=$3 cap=$4 scaled
    scaled=$(((base * cal_ms + idle_ms - 1) / idle_ms))
    ((scaled < base)) && scaled=$base
    ((scaled > base * cap)) && scaled=$((base * cap))
    echo "$scaled"
}
spin_ms() {
    local start=$(date +%s%N) i
    for ((i = 0; i < spin_iterations; i++)); do :; done
    echo $((($(date +%s%N) - start) / ns_per_ms))
}

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
for name in codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun tagCost tagAttrs linkFrames blankList blankIndent spaceFlood spaceAlternate spaceTrail spaceIndent punctTail htmlBlocks htmlLines htmlRow htmlNested fenceItems nestMixed; do
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
                expected_message='PASS 25 pathological inputs, 3 complete repetitions'
                ;;
        esac
        if [ "$status" -ne "$expected_status" ] || ! grep -qF "$expected_message" "$probe_root/output"; then
            echo "FAIL wrapper regression $probe status=$status"
            cat "$probe_root/output"
            exit 1
        fi
        echo "ok wrapper regression $probe status=$status"
    done
    # Each row: calibration ms, expected guard seconds; the idle spin takes 700 ms, so a box at that speed or faster keeps 280.
    for row in "300 280" "700 280" "1400 560" "2000 800" "99999 2240"; do
        read -r cal want <<< "$row"
        got=$(scaled_guard_s 280 "$cal" 700 8)
        [ "$got" = "$want" ] || { echo "FAIL wrapper regression guard for a ${cal} ms spin: got '$got', wanted $want"; exit 1; }
        echo "ok wrapper regression guard for a ${cal} ms spin is ${got}s"
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
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 30 qml6 tests/markdown-preview-state.qml -- "$text_module" || exit 1
    # The qs log gate is exact: one null connect line per started WorkerScript, so a missing worker or a missing warning fails as an extra line does.
    . tests/qslog-gate.sh
    null_line='WARN qt.core.qobject.connect: QObject::connect(QJSEngine, QtObject): invalid nullptr parameter'
    started_line='DEBUG qml: QSLOG_WORKER file:///x/MarkdownWorker.js'
    printf '%s\n%s\n%s\n' "$null_line" "$started_line" "$null_line" | qslog_nullptr control > /dev/null && { echo "FAIL qs log gate accepted a null connect beyond the started workers"; exit 1; }
    printf '%s\n' "$null_line" | qslog_nullptr control > /dev/null && { echo "FAIL qs log gate accepted a null connect with no worker started"; exit 1; }
    printf '%s\n' "$started_line" | qslog_nullptr control > /dev/null && { echo "FAIL qs log gate accepted a started worker with no warning"; exit 1; }
    printf '%s\n%s\n' "$null_line" "$started_line" | qslog_nullptr control > /dev/null || { echo "FAIL qs log gate refused one warning for one worker"; exit 1; }
    printf 'INFO clean\nDEBUG qml: QSLOG_WORKER \n' | qslog_nullptr control > /dev/null || { echo "FAIL qs log gate refused a clean log"; exit 1; }
    echo "ok qs log gate controls"
    # A decoded "1. ol" is laid out as text by the real MarkdownText, never as an ordered list item.
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 30 qml6 tests/markdown-literal.qml -- "$text_module" > "$probe_root/literal.log" 2>&1
    literal_status=$?
    grep -a 'MARKDOWN_LITERAL\|FAIL' "$probe_root/literal.log"
    [ "$literal_status" = 0 ] || exit 1
    # A done task box draws as a grey text glyph under the default fontconfig, and even where a colour emoji font comes first in the fallback order.
    QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software \
        timeout 30 qml6 tests/markdown-taskbox.qml -- "$text_module" "$probe_root/taskbox-default.png" > "$probe_root/taskbox-default.log" 2>&1
    python3 tests/markdown-taskbox.py "$probe_root/taskbox-default.png" || exit 1
    installed_fonts=$(fc-list)
    if [[ "$installed_fonts" == *'Noto Color Emoji'* ]]; then
        cat > "$probe_root/emoji.conf" <<CONF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>
  <cachedir>$probe_root/fccache</cachedir>
  <alias binding="same"><family>sans-serif</family><prefer><family>Noto Color Emoji</family></prefer></alias>
</fontconfig>
CONF
        FONTCONFIG_FILE="$probe_root/emoji.conf" QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software \
            timeout 30 qml6 tests/markdown-taskbox.qml -- "$text_module" "$probe_root/taskbox.png" > "$probe_root/taskbox.log" 2>&1
        python3 tests/markdown-taskbox.py "$probe_root/taskbox.png" || exit 1
    else
        echo "SKIP taskbox: Noto Color Emoji is not installed, and the override prefers that family, so no fallback can be judged"
    fi
    # The end-follow over a real lazy list needs no Theme, so it takes no module.
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 30 qml6 tests/markdown-endhold.qml || exit 1
fi

# A probe child keeps the base guard; a real run spins once so a starved box is given the time it needs.
guard_s=$hang_guard_s
[ "${1:-}" = "--probe" ] || guard_s=$(scaled_guard_s "$hang_guard_s" "$(spin_ms)" "$spin_idle_ms" "$guard_scale_cap")

run_once() {
    local output status started
    started=$SECONDS
    # Check qml6 or timeout directly before extracting complete work records.
    output=$(TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout "$guard_s" qml6 tests/markdown-linearity.qml -- ui/js/Md*.js 2>&1)
    status=$?
    if [ "$status" != 0 ]; then
        # Status 124 is the guard firing; any other is the harness's own exit, whose FAIL lines may sit past the head.
        printf 'harness exit %s after %ss of a %ss guard\n' "$status" "$((SECONDS - started))" "$guard_s" >&2
        printf '%s\n' "$output" | head -12 >&2
        printf '%s\n' "$output" | grep -a 'FAIL' | head -6 >&2
        return "$status"
    fi
    printf '%s\n' "$output" | sed -n 's/^qml: WORK //p'
}

expected=(codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun tagCost tagAttrs linkFrames blankList blankIndent spaceFlood spaceAlternate spaceTrail spaceIndent punctTail htmlBlocks htmlLines htmlRow htmlNested fenceItems nestMixed)
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
