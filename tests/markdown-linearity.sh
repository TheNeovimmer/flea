#!/usr/bin/env bash
# The linearity gate for the Markdown parser: each pathological input is parsed
# at 64 KiB and 512 KiB (8x) in Qt's own JS engine, and the time ratio must stay
# under 12. Median of three runs with a warmup; the engine's GC makes single
# shots bimodal, so one sample proves nothing.
set -u
cd "$(dirname "$0")/.." || exit 1

if ! command -v qml6 >/dev/null; then
    echo "markdown-linearity.sh: qml6 is not installed, cannot time the parser"
    exit 1
fi

run_once() {
    # The container's qml6 swallows QML console output without the logging env
    # tests/js.sh carries; without it no TIMES line ever arrives.
    TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        timeout 280 qml6 tests/markdown-linearity.qml 2>&1 \
        | grep -aE "^qml: TIMES" | sed 's/^qml: TIMES //'
}

# Warmup: the first parse in a fresh engine pays compilation and GC setup.
run_once > /dev/null
r1=$(run_once) || { echo "FAIL the timing harness never finished (run 1)"; exit 1; }
r2=$(run_once) || { echo "FAIL the timing harness never finished (run 2)"; exit 1; }
r3=$(run_once) || { echo "FAIL the timing harness never finished (run 3)"; exit 1; }
if [ -z "$r1" ] || [ -z "$r2" ] || [ -z "$r3" ]; then
    echo "FAIL the timing harness printed no TIMES lines"
    exit 1
fi

fail=0
names=$(printf '%s\n' "$r1" | awk '$1 != "codeOnly1M" { print $1 }')
for name in $names; do
    ratios=$(for r in "$r1" "$r2" "$r3"; do printf '%s\n' "$r" | awk -v n="$name" '$1 == n { print $4 }'; done | sort -n)
    median=$(printf '%s\n' "$ratios" | sed -n '2p')
    small=$(for r in "$r1" "$r2" "$r3"; do printf '%s\n' "$r" | awk -v n="$name" '$1 == n { print $2 }'; done | sort -n | sed -n '2p')
    large=$(for r in "$r1" "$r2" "$r3"; do printf '%s\n' "$r" | awk -v n="$name" '$1 == n { print $3 }'; done | sort -n | sed -n '2p')
    onem=$(printf '%s\n%s\n%s\n' "$r1" "$r2" "$r3" | awk '$1 == "codeOnly1M" { print $3 }' | sort -n | sed -n '2p')
    over=$(awk -v m="$median" 'BEGIN { print (m >= 12) }')
    if [ "$over" = "1" ]; then
        printf 'FAIL %s ratio %s over 12 (64K %sms, 512K %sms)\n' "$name" "$median" "$small" "$large"
        fail=1
    else
        printf 'ok %s ratio %s (64K %sms, 512K %sms)\n' "$name" "$median" "$small" "$large"
    fi
done
printf '1MiB dense code spans, median %sms\n' "${onem:-?}"
[ "$fail" = "0" ] || exit 1
printf 'PASS every pathological input stays linear\n'
