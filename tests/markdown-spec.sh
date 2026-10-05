#!/usr/bin/env bash
# Feed every CommonMark 0.31.2 and GFM extension example through the Markdown parser and Qt's drawing, and hold each section to its recorded count.
set -u
cd "$(dirname "$0")/.." || exit 1
# The CommonMark 0.31.2 examples (652), the GFM extension examples (24), the table forms (13) the entity forms (37) and the definition forms (2) in tests/fixtures/markdown-spec.
expected_examples=728
harness_seconds=280

if ! command -v qml6 >/dev/null; then
    echo "markdown-spec.sh: qml6 is not installed, cannot run the conformance harness"
    exit 1
fi

out=$(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout "$harness_seconds" qml6 tests/markdown-spec.qml 2>&1)
code=$?
# Qt warns about fonts and plugins on a headless box; the harness lines are the verdict.
printf '%s\n' "$out" | grep -a -E 'MDSPEC|FAIL|markdown-spec:' | sed 's/^qml: //'
if [ "$code" = 124 ]; then
    echo "markdown-spec.sh: the harness did not finish inside ${harness_seconds}s"
    exit 1
fi
# qml6 exits 0 on a ReferenceError inside an imported library, so the tally proves execution.
if ! printf '%s\n' "$out" | grep -qE "markdown-spec: [0-9]+ of $expected_examples examples drawn as the spec.s HTML, 0 failures"; then
    echo "markdown-spec.sh: the tally is missing, short of $expected_examples examples or reports failures"
    exit 1
fi
[ "$code" = 0 ] || exit "$code"
echo "PASS every section holds its recorded count"
