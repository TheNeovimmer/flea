# Sourced by the Markdown suites that start qs: a qs log holds exactly one "invalid nullptr parameter" line per WorkerScript the leg started, as Qt 6.11.2 prints one for each with a source.
QSLOG_NULLPTR='invalid nullptr parameter'
QSLOG_STARTED='QSLOG_WORKER [^ ]'

# Copies ui/ to $1 with a log line in every WorkerScript, so the started count comes from the product's own objects and no site goes uncounted.
qslog_ui_copy() {
  local dest=$1 sites patched
  cp -a ui "$dest" || return 1
  sites=$(grep -rhE 'WorkerScript \{$' ui --include='*.qml' | wc -l)
  find "$dest" -name '*.qml' -exec sed -i 's/WorkerScript {$/WorkerScript { Component.onCompleted: console.log("QSLOG_WORKER " + source)/' {} +
  patched=$(grep -rh 'QSLOG_WORKER' "$dest" --include='*.qml' | wc -l)
  if [ "$sites" -eq 0 ] || [ "$sites" -ne "$patched" ]; then
    printf 'FAIL qslog: %s WorkerScript sites in ui/, %s instrumented in the copy\n' "$sites" "$patched"
    return 1
  fi
}

# Sample input: a log holding two such lines and one "QSLOG_WORKER file:///x/MarkdownWorker.js" answers FAIL and status 1; with a second started line it answers 0.
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
