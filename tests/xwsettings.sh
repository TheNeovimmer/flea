#!/bin/bash
# Two ViewState singletons over one temp ui.json: a change saved by one applies live in the
# other through its FileView watch, per-window state stays put, an own write is never re-applied,
# and a half-written file is ignored until the next valid write. tests/js/uistate.js pins the
# classifier and the merge; this pins the QML wiring it runs through, which no pure suite reaches.
set -u
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

BIN=$PWD/target/debug/flea
SANDBOX=$FIXTURE_ROOT/xwsettings-$$
QMLDIR=$SANDBOX/flea
fail=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=1
  else
    echo "ok   $label"
  fi
}

if ! command -v qs >/dev/null; then
  echo "xwsettings.sh: qs is not installed, cannot drive the QML probes"
  exit 1
fi
if [ ! -x "$BIN" ]; then
  printf 'xwsettings.sh: no binary at %s\n' "$BIN" >&2
  printf 'xwsettings.sh: build it (cargo build); refusing to report on nothing\n' >&2
  exit 1
fi

# The singleton and the libraries it imports, copied the way tests/uiwriter.sh copies them:
# importing ui/ whole makes Quickshell scan every file in it and warn about the two OEM symlinks
# a headless run has no session for.
sandbox_make "$SANDBOX" || exit 1
mkdir -p "$QMLDIR/js" || exit 1
cp ui/ViewState.qml "$QMLDIR/ViewState.qml" || exit 1
libs=$(sed -n 's|^import "js/\([A-Za-z]*\)\.js".*|\1|p' ui/ViewState.qml)
copied=" "
while [ -n "${libs// /}" ]; do
  next=""
  for lib in $libs; do
    case "$copied" in *" $lib "*) continue ;; esac
    cp "ui/js/$lib.js" "$QMLDIR/js/$lib.js" || exit 1
    copied="$copied$lib "
    next="$next $(sed -n 's|^\.import "\([A-Za-z]*\)\.js".*|\1|p' "ui/js/$lib.js" | tr '\n' ' ')"
  done
  libs=$next
done
ln -sfn /usr/share/omarchy/shell/Commons "$QMLDIR/Commons" || exit 1
printf 'module flea\nsingleton ViewState 1.0 ViewState.qml\n' > "$QMLDIR/qmldir" || exit 1

# Window A: saves one preference the way pane.toggleHidden does, then stays alive one beat past
# its drained writer so a re-applied own write would have to show as a queued patch or a failure.
cat > "$QMLDIR/writer.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int failures: 0
    property bool started: false

    property var reporter: Connections {
        target: ViewState
        function onSaveFailed() { root.failures = root.failures + 1 }
    }

    Component.onCompleted: {
        ViewState.changeKey("hidden", true)
        root.started = true
    }

    property var watcher: Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.started && ViewState.writeBook.inflight.length === 0) {
                console.log("PROBE failures=" + root.failures)
                console.log("PROBE patch=" + ViewState.patch())
                Qt.quit()
            }
        }
    }

    property var backstop: Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.log("PROBE stalled failures=" + root.failures)
            Qt.quit()
        }
    }
}
QML

# Window B: holds another window's read and watches it. It quits the moment the preference lands,
# reporting what else moved with it, so a late or partial application reads as that and not a pass.
cat > "$QMLDIR/watcher.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int failures: 0
    property bool started: false

    property var reporter: Connections {
        target: ViewState
        function onSaveFailed() { root.failures = root.failures + 1 }
    }

    Component.onCompleted: {
        console.log("PROBE watching hidden=" + ViewState.state.hidden + " view=" + ViewState.view)
        root.started = true
    }

    property var watcher: Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (!root.started) return
            if (ViewState.state.hidden === true) {
                console.log("PROBE applied hidden=" + ViewState.state.hidden + " view=" + ViewState.view
                            + " lastPath=" + ViewState.state.lastPath + " density=" + ViewState.state.density)
                console.log("PROBE failures=" + root.failures)
                console.log("PROBE patch=" + ViewState.patch())
                Qt.quit()
            }
        }
    }

    property var backstop: Timer {
        interval: 15000
        running: true
        onTriggered: {
            console.log("PROBE stalled hidden=" + ViewState.state.hidden)
            Qt.quit()
        }
    }
}
QML

sandbox_scratch "$SANDBOX/state" || exit 1
env XDG_STATE_HOME="$SANDBOX/state" "$BIN" --ui-state \
  '{"hidden":false,"view":"grid","lastPath":"/seed","density":"compact"}' >/dev/null 2>&1 \
  || { echo "FAIL xwsettings: the seed write failed"; exit 1; }

env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/state" \
    FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/watcher.qml" > "$SANDBOX/watching.log" 2>&1 &
watching_pid=$!
waited=0
until grep -q 'PROBE watching' "$SANDBOX/watching.log" 2>/dev/null; do
  waited=$((waited + 1))
  if [ "$waited" -gt 600 ]; then
    echo "FAIL xwsettings: the watching window never reported its read"
    fail=1
    kill "$watching_pid" 2>/dev/null
    wait "$watching_pid" 2>/dev/null
    break
  fi
  sleep 0.05
done
if [ "$fail" -eq 0 ]; then
  env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/state" \
      FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/writer.qml" > "$SANDBOX/writing.log" 2>&1
  wait "$watching_pid"
  applied=$(grep 'PROBE applied' "$SANDBOX/watching.log" | head -1)
  check "the watching window printed what it applied" "1" "$([ -n "$applied" ] && echo 1 || echo 0)"
  check "the other window's hidden toggle applied there" "1" "$(echo "$applied" | grep -c 'hidden=true')"
  check "and its view stayed its own" "1" "$(echo "$applied" | grep -c 'view=grid')"
  check "and where it was stayed too" "1" "$(echo "$applied" | grep -c 'lastPath=/seed')"
  check "the watching window was never asked to save" "1" "$(grep -c 'PROBE patch={}' "$SANDBOX/watching.log")"
  check "and reported no failure" "1" "$(grep -c 'PROBE failures=0' "$SANDBOX/watching.log")"
  check "the writing window drained with nothing owed" "1" "$(grep -c 'PROBE patch={}' "$SANDBOX/writing.log")"
  check "and nothing reported" "1" "$(grep -c 'PROBE failures=0' "$SANDBOX/writing.log")"
  flat=$(tr -d ' \n' < "$SANDBOX/state/flea/ui.json" 2>/dev/null)
  check "the file holds the toggle" "1" "$(echo "$flat" | grep -c '"hidden":true')"
  check "and the view nobody touched" "1" "$(echo "$flat" | grep -c '"view":"grid"')"
fi

# A half-written file is ignored until the next valid write: the watching window keeps drawing
# what it had, and the write after the garbage still applies.
if [ "$fail" -eq 0 ]; then
  sandbox_scratch "$SANDBOX/garbage" || exit 1
  mkdir -p "$SANDBOX/garbage/state/flea" || exit 1
  env XDG_STATE_HOME="$SANDBOX/garbage/state" "$BIN" --ui-state \
    '{"hidden":false,"view":"grid","density":"compact"}' >/dev/null 2>&1 \
    || { echo "FAIL xwsettings: the garbage-phase seed write failed"; exit 1; }
  env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/garbage/state" \
      FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/watcher.qml" > "$SANDBOX/garbage.log" 2>&1 &
  garbage_pid=$!
  waited=0
  until grep -q 'PROBE watching' "$SANDBOX/garbage.log" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -gt 600 ]; then
      echo "FAIL xwsettings: the garbage-phase watcher never reported its read"
      fail=1
      kill "$garbage_pid" 2>/dev/null
      wait "$garbage_pid" 2>/dev/null
      break
    fi
    sleep 0.05
  done
  if [ "$fail" -eq 0 ]; then
    # Truncated mid-object, the way an editor's own write looks between its truncate and its close.
    printf '%s' '{"hidden":true,"view":"grid","density":"compact"' \
      > "$SANDBOX/garbage/state/flea/ui.json" || exit 1
    wait "$garbage_pid"
    check "a half-written file applies nothing" "1" "$(grep -c 'PROBE stalled hidden=false' "$SANDBOX/garbage.log")"
    # The write after the garbage still applies: the ignore ends at the next valid write.
    env XDG_STATE_HOME="$SANDBOX/garbage/state" "$BIN" --ui-state \
      '{"hidden":true,"view":"grid","density":"compact"}' >/dev/null 2>&1 \
      || { echo "FAIL xwsettings: the recovery write failed"; fail=1; }
    out=$(env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/garbage/state" \
        FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/watcher.qml" 2>&1)
    check "the next valid write applies again" "1" "$(echo "$out" | grep -c 'PROBE applied hidden=true')"
  fi
fi

sandbox_remove "$SANDBOX" || exit 1

[ "$fail" -eq 0 ] && echo "xwsettings: all checks passed"
exit $fail
