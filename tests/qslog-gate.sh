# Sourced by the Markdown suites that start qs: a qs log run with QSLOG_RULES holds exactly one "invalid nullptr parameter" line per WorkerScript the leg started, as Qt 6.11.2 prints one for each with a source.
QSLOG_NULLPTR='invalid nullptr parameter'
QSLOG_STARTED='WORKER_STARTED [^ ]'

# The rule that makes the real ui/ announce each WorkerScript start, as one WORKER_STARTED line under the flea.worker category.
QSLOG_RULES='flea.worker.info=true'

# Sample input: the run's existing rules "qt.qml.diskcache*=true" answer "qt.qml.diskcache*=true;flea.worker.info=true"; none answer the rule alone.
qslog_rules() { printf '%s' "${1:+$1;}$QSLOG_RULES"; }

# Sample input: a log holding two such lines and one "WORKER_STARTED file:///x/MarkdownWorker.js" answers FAIL and status 1; with a second started line it answers 0.
qslog_nullptr() {
  local label=$1 log found started
  log=$(cat)
  found=$(grep -acF -- "$QSLOG_NULLPTR" <<< "$log")
  started=$(grep -acE -- "$QSLOG_STARTED" <<< "$log")
  if [ "$found" -ne "$started" ]; then
    printf 'FAIL %s: the qs log holds %s "%s" lines for %s WorkerScripts started with a source\n' "$label" "$found" "$QSLOG_NULLPTR" "$started"
    return 1
  fi
}

# Sample input: a log with one null connect line and one WORKER_STARTED line prints the log less the null connect line; any other pairing prints FAIL on stderr, the whole log, and status 1.
qslog_filter() {
  local label=$1 log
  log=$(cat)
  if qslog_nullptr "$label" <<< "$log" >&2; then
    grep -aFv -- "$QSLOG_NULLPTR" <<< "$log" || true
  else
    printf '%s\n' "$log"
    return 1
  fi
}

# Sample input: a log of a run with no QT_LOGGING_RULES holding one null connect line and no WORKER_STARTED line answers 0; a WORKER_STARTED line, or no null connect line at all, answers FAIL and status 1.
qslog_silent() {
  local label=$1 log found started
  log=$(cat)
  found=$(grep -acF -- "$QSLOG_NULLPTR" <<< "$log")
  started=$(grep -acE -- "$QSLOG_STARTED" <<< "$log")
  if [ "$started" -ne 0 ] || [ "$found" -eq 0 ]; then
    printf 'FAIL %s: a default run printed %s WORKER_STARTED lines and %s null connect lines, so the announcement is not silent or no worker started\n' "$label" "$started" "$found"
    return 1
  fi
}
