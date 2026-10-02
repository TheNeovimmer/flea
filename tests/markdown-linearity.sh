#!/usr/bin/env bash
# Gate deterministic parser work at 64 KiB and 512 KiB; milliseconds are diagnostics only.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# Verify wrapper rejection with partial timeout, missing input, missing repetition and excessive work.
if [ "${1:-}" != "--probe" ]; then
    probe_root=$(mktemp -d "${TMPDIR:-/tmp}/markdown-linearity.XXXXXX") || exit 1
    trap 'rm -rf -- "$probe_root"' EXIT
    cat > "$probe_root/timeout" <<'STUB'
#!/usr/bin/env bash
if [ "$LINEARITY_CASE" = timeout ]; then echo 'qml: WORK codeDense 1 8 1 8'; exit 124; fi
if [ "$LINEARITY_CASE" = empty ]; then exit 0; fi
if [ "$LINEARITY_CASE" = qml-error ]; then echo 'qml: WORK codeDense 1 8 1 8'; exit 1; fi
sample=0
[ ! -f "$LINEARITY_COUNTER" ] || read -r sample < "$LINEARITY_COUNTER"
sample=$((sample + 1)); echo "$sample" > "$LINEARITY_COUNTER"
for name in codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun; do
    [ "$LINEARITY_CASE" != missing ] || [ "$name" != listDeep ] || continue
    [ "$LINEARITY_CASE" != short ] || [ "$sample" != 2 ] || [ "$name" != listDeep ] || continue
    large=8; [ "$LINEARITY_CASE" != nonlinear ] || large=13
    printf 'qml: WORK %s 1 %s 1 999\n' "$name" "$large"
done
STUB
    chmod +x "$probe_root/timeout"
    for probe in timeout qml-error empty missing short nonlinear diagnostics; do
        rm -f "$probe_root/counter"
        if env PATH="$probe_root:$PATH" LINEARITY_CASE="$probe" LINEARITY_COUNTER="$probe_root/counter" \
            bash "$0" --probe > "$probe_root/output" 2>&1; then status=0; else status=$?; fi
        if { [ "$probe" = diagnostics ] && [ "$status" != 0 ]; } || { [ "$probe" != diagnostics ] && [ "$status" = 0 ]; }; then
            echo "FAIL wrapper regression $probe status=$status"; cat "$probe_root/output"; exit 1
        fi
        echo "ok wrapper regression $probe status=$status"
    done
fi

if ! command -v qml6 >/dev/null; then
    echo "FAIL qml6 is not installed"
    exit 1
fi

run_once() {
    local output status
    # Check qml6 or timeout directly before extracting complete work records.
    output=$(TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 280 qml6 tests/markdown-linearity.qml 2>&1)
    status=$?
    if [ "$status" != 0 ]; then
        printf '%s\n' "$output" | head -12 >&2
        return "$status"
    fi
    printf '%s\n' "$output" | sed -n 's/^qml: WORK //p'
}

expected='codeDense codeOnly bangOpen bracketOpen angleOpen delimSoup quoteDeep listDeep backtickRun'
repetitions=3
size_ratio=8
work_margin=1.5
for ((run=1; run<=repetitions; run++)); do
    result=$(run_once) || { echo "FAIL parser harness never finished (run $run)"; exit 1; }
    # Sample input: codeDense 1200 9600 1 8 (work at each size, then diagnostic milliseconds).
    printf '%s\n' "$result" | awk -v expected="$expected" -v run="$run" \
        -v limit="$(awk -v ratio="$size_ratio" -v margin="$work_margin" 'BEGIN { print ratio * margin }')" '
        BEGIN { count=split(expected, names, " "); for (i=1;i<=count;i++) wanted[names[i]]=1 }
        {
            if (!($1 in wanted) || seen[$1]++ || NF != 5 || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $2 == 0 || $3 == 0) {
                print "FAIL invalid work sample in run " run ": " $0; failed=1; next
            }
            if ($3 > $2 * limit) { print "FAIL " $1 " work ratio " $3/$2 " exceeds " limit; failed=1 }
            else print "ok " $1 " work=" $2 "/" $3 " ms=" $4 "/" $5 " run=" run
        }
        END { for (i=1;i<=count;i++) if (seen[names[i]] != 1) { print "FAIL missing sample " names[i] " in run " run; failed=1 }; exit failed }
    ' || exit 1
done
printf 'PASS 9 pathological inputs, 3 complete repetitions, work bound 8x plus 50%% margin\n'
