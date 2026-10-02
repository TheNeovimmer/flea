#!/bin/bash
# Two ViewState singletons over one temp ui.json: live apply of one window's change in the other, per-window state, own-write and half-written guards; tests/js/uistate.js pins the merge, this pins the QML wiring.
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
    # A live second replace in the same process: the stayer stays alive across the garbage and the
    # recovery write, so the recovery applying in its own log proves no fresh process was needed.
    cat > "$QMLDIR/stayer.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property string lastDensity: ""
    Component.onCompleted: {
        console.log("PROBE watching hidden=" + ViewState.state.hidden)
        root.lastDensity = String(ViewState.state.density || "compact")
    }
    property var watcher: Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            var density = String(ViewState.state.density || "compact")
            if (density !== root.lastDensity) {
                root.lastDensity = density
                console.log("PROBE live density=" + density)
            }
            if (ViewState.state.hidden === true) {
                console.log("PROBE applied hidden=" + ViewState.state.hidden)
                console.log("PROBE patch=" + ViewState.patch())
                Qt.quit()
            }
        }
    }
    property var backstop: Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.log("PROBE stalled hidden=" + ViewState.state.hidden)
            Qt.quit()
        }
    }
}
QML
    kill "$garbage_pid" 2>/dev/null || true
    wait "$garbage_pid" 2>/dev/null || true
    env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/garbage/state" \
        FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/stayer.qml" > "$SANDBOX/stayer.log" 2>&1 &
    stayer_pid=$!
    waited=0
    until grep -q 'PROBE watching' "$SANDBOX/stayer.log" 2>/dev/null; do
      waited=$((waited + 1))
      if [ "$waited" -gt 600 ]; then
        echo "FAIL xwsettings: the stayer never reported its read"
        fail=1
        kill "$stayer_pid" 2>/dev/null
        wait "$stayer_pid" 2>/dev/null
        break
      fi
      sleep 0.05
    done
    if [ "$fail" -eq 0 ]; then
      # Truncated mid-object, the way an editor's own write looks between its truncate and its close.
      printf '%s' '{"hidden":true,"view":"grid","density":"compact"' \
        > "$SANDBOX/garbage/state/flea/ui.json" || exit 1
      # A marker valid write behind the garbage: the watcher answering it proves it handled every event after the garbage too.
      env XDG_STATE_HOME="$SANDBOX/garbage/state" "$BIN" --ui-state \
        '{"hidden":false,"view":"grid","density":"normal"}' >/dev/null 2>&1 \
        || { echo "FAIL xwsettings: the marker write failed"; fail=1; }
      waited=0
      until grep -q 'PROBE live density=normal' "$SANDBOX/stayer.log" 2>/dev/null; do
        waited=$((waited + 1))
        if [ "$waited" -gt 200 ]; then
          echo "FAIL xwsettings: the watcher never answered the marker behind the garbage"
          fail=1
          break
        fi
        sleep 0.05
      done
      check "the watcher answered a later event behind the garbage" "1" "$(grep -c 'PROBE live density=normal' "$SANDBOX/stayer.log")"
      check "and the half-written file applied nothing live" "0" "$(grep -c 'PROBE applied' "$SANDBOX/stayer.log")"
      # The live second replace in the same process: the recovery write lands in the stayer's own log.
      env XDG_STATE_HOME="$SANDBOX/garbage/state" "$BIN" --ui-state \
        '{"hidden":true,"view":"grid","density":"compact"}' >/dev/null 2>&1 \
        || { echo "FAIL xwsettings: the recovery write failed"; fail=1; }
      wait "$stayer_pid"
      check "the next valid write applies again live" "1" "$(grep -c 'PROBE applied hidden=true' "$SANDBOX/stayer.log")"
    fi
  fi
fi

# Settled values, not raw bytes: a bogus column heals, a null places group keeps favourites,
# and a removed key reads as its default. Each hand edit below fails on raw_bytes and passes on settled.
if [ "$fail" -eq 0 ]; then
  sandbox_scratch "$SANDBOX/settled" || exit 1
  mkdir -p "$SANDBOX/settled/state/flea" || exit 1
  env XDG_STATE_HOME="$SANDBOX/settled/state" "$BIN" --ui-state \
    '{"hidden":true,"density":"compact","columns":["name","size","date"],"places":{"showUnmounted":true,"favourites":[{"label":"Old","path":"/old"}]}}' >/dev/null 2>&1 \
    || { echo "FAIL xwsettings: the settled-phase seed write failed"; exit 1; }
  cat > "$QMLDIR/settled.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: root
    Component.onCompleted: {
        console.log("PROBE watching columns=" + JSON.stringify(ViewState.state.columns)
                    + " placesType=" + (ViewState.state.places === null ? "null" : typeof ViewState.state.places)
                    + " hidden=" + ViewState.state.hidden)
    }
    property var watcher: Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            console.log("PROBE live columns=" + JSON.stringify(ViewState.state.columns)
                        + " placesType=" + (ViewState.state.places === null ? "null" : typeof ViewState.state.places)
                        + " hidden=" + ViewState.state.hidden
                        + " favourites=" + JSON.stringify((ViewState.state.places || {}).favourites))
        }
    }
    property var backstop: Timer {
        interval: 30000
        running: true
        onTriggered: Qt.quit()
    }
}
QML
  env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/settled/state" \
      FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/settled.qml" > "$SANDBOX/settled.log" 2>&1 &
  settled_pid=$!
  waited=0
  until grep -q 'PROBE watching' "$SANDBOX/settled.log" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -gt 600 ]; then
      echo "FAIL xwsettings: the settled watcher never reported its read"
      fail=1
      kill "$settled_pid" 2>/dev/null
      wait "$settled_pid" 2>/dev/null
      break
    fi
    sleep 0.05
  done
  if [ "$fail" -eq 0 ]; then
    python3 - "$SANDBOX/settled/state/flea/ui.json" <<'PY'
import json, sys
p = sys.argv[1]
doc = json.load(open(p))
doc["columns"] = ["name", "size", "bogus"]
json.dump(doc, open(p, "w"))
PY
    # A bounded poll for the healed default, not a fixed sleep: the absence check below is only read once the watcher proves it handled the edit.
    waited=0
    until [ "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -1 | grep -c '"name","size","date"')" -ge 1 ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt 200 ]; then break; fi
      sleep 0.05
    done
    check "a bogus column is never taken" "0" "$(grep -c 'bogus' "$SANDBOX/settled.log" | head -1)"
    # The healed default appears live; on raw_bytes the bogus string stays in the log.
    check "and the settled default lands instead" "1" "$([ "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -1 | grep -c '"name","size","date"')" -ge 1 ] && echo 1 || echo 0)"
    live_before=$(grep -c 'PROBE live' "$SANDBOX/settled.log")
    python3 - "$SANDBOX/settled/state/flea/ui.json" <<'PY'
import json, sys
p = sys.argv[1]
doc = json.load(open(p))
doc["places"] = None
json.dump(doc, open(p, "w"))
PY
    waited=0
    until [ "$(grep -c 'PROBE live' "$SANDBOX/settled.log")" -gt "$live_before" ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt 200 ]; then break; fi
      sleep 0.05
    done
    check "a null places group never empties favourites" "0" "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -n +"$((live_before + 1))" | grep -c 'placesType=null')"
    check "and the kept entries survive it" "1" "$([ "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -1 | grep -c '/old')" -ge 1 ] && echo 1 || echo 0)"
    live_before=$(grep -c 'PROBE live' "$SANDBOX/settled.log")
    printf '%s' '{"density":"normal"}' > "$SANDBOX/settled/state/flea/ui.json" || exit 1
    waited=0
    until [ "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -n +"$((live_before + 1))" | grep -c 'hidden=false')" -ge 1 ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt 200 ]; then break; fi
      sleep 0.05
    done
    check "a removed key reads as its default" "1" "$([ "$(grep 'PROBE live' "$SANDBOX/settled.log" | tail -n +"$((live_before + 1))" | grep -c 'hidden=false')" -ge 1 ] && echo 1 || echo 0)"
    echo "settled tail:"
    grep 'PROBE live' "$SANDBOX/settled.log" | tail -3 || true
  fi
  kill "$settled_pid" 2>/dev/null || true
  wait "$settled_pid" 2>/dev/null || true
fi

# A refused patch never blocks later saves: bogus columns are refused, then a valid density lands
# in the same process. On raw_bytes the second write is refused for the window's life.
if [ "$fail" -eq 0 ]; then
  sandbox_scratch "$SANDBOX/refuse" || exit 1
  mkdir -p "$SANDBOX/refuse/state/flea" || exit 1
  env XDG_STATE_HOME="$SANDBOX/refuse/state" "$BIN" --ui-state \
    '{"hidden":false,"density":"compact"}' >/dev/null 2>&1 \
    || { echo "FAIL xwsettings: the refuse-phase seed write failed"; exit 1; }
  cat > "$QMLDIR/refuse.qml" <<'QML'
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int failures: 0
    property bool stepped: false
    property var reporter: Connections {
        target: ViewState
        function onSaveFailed() { root.failures = root.failures + 1 }
    }
    Component.onCompleted: {
        ViewState.changeKey("columns", ["name", "size", "bogus"])
    }
    property var step: Timer {
        interval: 1500
        running: true
        repeat: false
        onTriggered: {
            root.stepped = true
            console.log("PROBE afterRefuse failures=" + root.failures + " patch=" + ViewState.patch())
            ViewState.changeKey("density", "normal")
        }
    }
    property var done: Timer {
        interval: 300
        repeat: true
        running: true
        onTriggered: {
            if (root.stepped && root.failures > 0 && ViewState.writeBook.inflight.length === 0) {
                console.log("PROBE final failures=" + root.failures + " patch=" + ViewState.patch()
                            + " density=" + ViewState.state.density)
                Qt.quit()
            }
        }
    }
    property var backstop: Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.log("PROBE stalled failures=" + root.failures + " patch=" + ViewState.patch())
            Qt.quit()
        }
    }
}
QML
  out=$(env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 XDG_STATE_HOME="$SANDBOX/refuse/state" \
      FLEA_BIN="$BIN" timeout 60 qs -p "$QMLDIR/refuse.qml" 2>&1)
  check "the refused patch is reported once" "1" "$(echo "$out" | grep -c 'PROBE afterRefuse failures=1')"
  check "and a later valid write applies again in the same process" "1" "$(echo "$out" | grep -c 'PROBE final failures=1 patch={} density=normal')"
  flat=$(tr -d ' \n' < "$SANDBOX/refuse/state/flea/ui.json" 2>/dev/null)
  check "and the file holds the valid write" "1" "$(echo "$flat" | grep -c '"density":"normal"')"
  echo "$out" | grep -a 'PROBE ' | tail -5 || true
fi

sandbox_remove "$SANDBOX" || exit 1

[ "$fail" -eq 0 ] && echo "xwsettings: all checks passed"
exit $fail
