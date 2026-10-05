#!/usr/bin/env bash
# Columns view watches the side columns it draws (issue 244): another process changes a neighbour folder and the window shows it.
# shellcheck disable=SC2034,SC2154 # ui.sh supplies the launch, ipc, key and shot helpers.

# A step that has not shown its change by then is stale; the poll only bounds the wait and asserts no duration. A dry check overrides the budget.
: "${colwatch_budget_s:=10}"
colwatch_poll_s=0.05
# More folders than the backend's watch cap of eight, so walking the cursor over them draws more folders than it can watch at once.
colwatch_folders=10

# The row each side column keeps through every step, so a read that lacks it is an undrawn column and not a verdict.
colwatch_anchor() {
    case "$1" in
        child) printf 'seed.txt' ;;
        parent) printf 'beside.txt' ;;
        *) return 1 ;;
    esac
}

# Wait until a drawn side column (parent or child) has or lacks a name; only a successful read of a drawn column counts, and a failed one keeps polling.
colwatch_wait() {
    local step="$1" slot="$2" verdict="$3" name="$4" anchor names read_status deadline last="no read answered"
    anchor=$(colwatch_anchor "$slot") || fail "colwatch: step $step names no known column: $slot"
    deadline=$((SECONDS + colwatch_budget_s))
    while (( SECONDS <= deadline )); do
        read_status=0
        names=$(ipc columnNames "$slot" 2>/dev/null) || read_status=$?
        if (( read_status != 0 )); then
            last="ipc columnNames $slot exited $read_status"
        elif [[ "|$names|" != *"|$anchor|"* ]]; then
            last="the $slot column is not drawn, it read: $names"
        else
            names="|$names|"
            case "$verdict" in
                has) [[ "$names" == *"|$name|"* ]] && return 0 ;;
                gone) [[ "$names" != *"|$name|"* ]] && return 0 ;;
            esac
            last="the $slot column holds $names"
        fi
        sleep "$colwatch_poll_s"
    done
    fail "colwatch: step $step never showed $name $verdict in the $slot column, last read: $last"
}

# Wait until the cursor rests on a folder row by name, read from the view on screen (rowAt reads the hidden list's delegates in Columns), and the child column draws its seed file.
colwatch_cursor_on() {
    local name="$1" deadline
    deadline=$((SECONDS + colwatch_budget_s))
    while (( SECONDS <= deadline )); do
        [[ "$(ipc visibleRowName "$(ipc cursor)")" == "$name" ]] && break
        sleep "$colwatch_poll_s"
    done
    [[ "$(ipc visibleRowName "$(ipc cursor)")" == "$name" ]] || fail "colwatch: the cursor is on '$(ipc visibleRowName "$(ipc cursor)")', not $name"
    colwatch_wait "cursor-$name" child has seed.txt
}

case_colwatch() {
    local dir="$fixture_root/colwatch" col flea_before folder i names
    sandbox_scratch "$dir"
    col="$dir/col"
    mkdir -p "$col"
    for i in $(seq -w 1 "$colwatch_folders"); do
        mkdir "$col/d$i"
        printf 'seed\n' > "$col/d$i/seed.txt"
    done
    printf 'beside\n' > "$dir/beside.txt"
    launch "$col"
    wait_listing "$colwatch_folders"
    click_chrome columns
    settle
    [[ "$(ipc viewMode)" == "columns" ]] || fail "colwatch: the chrome button did not switch the view"
    (( $(ipc columnCount) >= 3 )) || fail "colwatch: needs 3 columns, has $(ipc columnCount)"
    flea_before=$(flea_pid)
    key g >/dev/null
    colwatch_cursor_on d01
    colwatch_wait ready parent has beside.txt

    # The child column: a create, a rename and a delete from a plain shell, each waited for in the column's own rows.
    printf 'new\n' > "$col/d01/new.txt"
    colwatch_wait create child has new.txt
    printf 'COLWATCH create ok\n'
    shot colwatch-create
    mv "$col/d01/new.txt" "$col/d01/renamed.txt"
    colwatch_wait rename child has renamed.txt
    colwatch_wait rename child gone new.txt
    printf 'COLWATCH rename ok\n'
    rm -- "$col/d01/renamed.txt"
    colwatch_wait delete child gone renamed.txt
    printf 'COLWATCH delete ok\n'

    # The parent column is the folder above the open one: a create there shows in the window's left column.
    printf 'made\n' > "$dir/made.txt"
    colwatch_wait parent parent has made.txt
    printf 'COLWATCH parent ok\n'

    # Walk the cursor over every folder so more are drawn than the backend can watch, then come back: the first child column must follow again.
    for folder in $(seq -w 2 "$colwatch_folders"); do
        key j >/dev/null
        colwatch_cursor_on "d$folder"
    done
    printf 'late\n' > "$col/d$colwatch_folders/late.txt"
    colwatch_wait cap-last child has late.txt
    key g >/dev/null
    colwatch_cursor_on d01
    printf 'again\n' > "$col/d01/again.txt"
    colwatch_wait cap-first child has again.txt
    printf 'COLWATCH cap ok\n'

    # Negative control: d05 is no longer drawn, so a create in it reaches no column and no cache; the sentinel in the drawn child proves the stream was read past it.
    printf 'ghost\n' > "$col/d05/ghost.txt"
    printf 'sentinel\n' > "$col/d01/sentinel.txt"
    colwatch_wait negative child has sentinel.txt
    settle
    for names in "$(ipc columnNames child)" "$(ipc columnNames parent)" "$(ipc columnPeekNames "$col/d05")" "$(ipc columnPeekNames "$col")"; do
        [[ "|$names|" != *"|ghost.txt|"* ]] || fail "colwatch: a create in the undrawn d05 reached a column or its cache: $names"
    done
    [[ "$(ipc total)" == "$colwatch_folders" ]] || fail "colwatch: the open folder lists $(ipc total) rows after a create in an undrawn child"
    [[ "$(flea_pid)" == "$flea_before" ]] || fail "colwatch: Flea restarted during the case"
    printf 'COLWATCH negative ok\n'
    assert_window
    kill_flea
}
