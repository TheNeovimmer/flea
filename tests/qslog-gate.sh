# Sourced by the Markdown suites that start qs: a qs log may carry no more "invalid nullptr parameter" lines than the leg started WorkerScripts.
# Qt 6.11.2 prints one per WorkerScript with a source, even for an empty script under a bare qml6, so any further line is a real null connect.
QSLOG_NULLPTR='invalid nullptr parameter'

# Sample input: a log with two such lines under "qslog_nullptr 1 lazy" answers FAIL and status 1; the same log under "qslog_nullptr 2 lazy" answers 0.
qslog_nullptr() {
  local allowed=$1 label=$2 found
  found=$(grep -acF -- "$QSLOG_NULLPTR")
  if [ "$found" -gt "$allowed" ]; then
    printf 'FAIL %s: the qs log holds %s "%s" lines, %s allowed (one per WorkerScript started)\n' "$label" "$found" "$QSLOG_NULLPTR" "$allowed"
    return 1
  fi
}
