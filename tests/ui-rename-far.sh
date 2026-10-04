#!/usr/bin/env bash
# Sourced by ui.sh after ui-rename-design.sh; case_renamedesign calls rename_design_far for each view on its own 1202-file fixture.
# shellcheck disable=SC2154 # ui.sh and case_renamedesign supply the fixture, the native driver and the dynamic locals.

# A row outside the held window is asked for after the rename, so its rectangle may take a moment to exist: up to 100 reads, 50 ms apart.
rename_far_rect_polls=100
rename_far_rect_s=0.05
# Ctrl+D pages half a screen, so a deep cursor is a bounded number of presses away.
rename_far_page_presses=200
# The first two rows of the fixture are a-original.md and b-existing.md, so f0000.txt is row 2.
rename_far_first_file_row=2

# Pages down until the cursor is at least the wanted row, and leaves the cursor row's file name in rename_far_name.
rename_far_deepen() {
    local at="$1" presses cursor
    key -k Home >/dev/null || fail 'renamefar: Home failed'
    menus_expect renameState '.cursor == 0' "$mode far setup at the top"
    for presses in $(seq 1 "$rename_far_page_presses"); do
        cursor=$(ipc cursor)
        (( cursor >= at )) && break
        key -M ctrl -k d -m ctrl >/dev/null || fail 'renamefar: page down failed'
    done
    rename_design_still
    (( $(ipc cursor) >= at )) || fail "renamefar: the cursor reached row $(ipc cursor), not row $at"
    rename_far_name=$(ipc renameState | jq -er .cursorName) || fail 'renamefar: the cursor row has no name'
}

# The cursor row's rectangle once it exists, checked whole inside the list area and above the status bar.
rename_far_whole() {
    local label="$1" index="$2" rect="" polls rx ry rw rh ax ay aw ah footer sy
    for polls in $(seq 1 "$rename_far_rect_polls"); do
        rect=$(ipc rowRect "$index")
        [[ "$rect" =~ ^-?[0-9]+(\ -?[0-9]+){3}$ ]] && break
        sleep "$rename_far_rect_s"
    done
    [[ "$rect" =~ ^-?[0-9]+(\ -?[0-9]+){3}$ ]] || fail "renamefar: $label: row $index never drew a rectangle, last [$rect]"
    read -r rx ry rw rh <<< "$rect"
    read -r ax ay aw ah <<< "$(ipc listAreaRect)"
    [[ "$ax $ay $aw $ah" =~ ^-?[0-9]+(\ -?[0-9]+){3}$ ]] || fail "renamefar: $label: the list area has no rectangle"
    footer=$(ipc statusFooterState) || fail "renamefar: $label: status bar observation failed"
    # Sample input: "0 681 1000 27" (the status strip's x y width height, window pixels).
    read -r _ sy _ _ <<< "$(jq -er .frame <<< "$footer")"
    [[ "$sy" =~ ^-?[0-9]+$ ]] || fail "renamefar: $label: the status bar has no top edge"
    (( ry >= ay && ry + rh <= ay + ah )) || fail "renamefar: $label: row $index $rect is not whole inside the list $ax $ay $aw $ah"
    (( ry + rh <= sy )) || fail "renamefar: $label: row $index $rect reaches the status bar at y $sy"
    menus_checks=$((menus_checks + 1))
    printf 'MENUS_CHECK %s %s row=%q list=%q statusTop=%q\n' "$menus_checks" "$label row is whole above the status bar" "$rect" "$ax $ay $aw $ah" "$sy"
}

# Renames the cursor row, then proves the cursor, the one selection and the view all followed the file to its new row.
rename_far_commit() {
    local label="$1" from="$2" to="$3" want="$4" state
    rename_design_open F2 "$from"
    rename_design_draft "$to"
    menus_guard "$menu_dir/$from"
    menus_guard "$menu_dir/$to"
    key -k Return >/dev/null || fail 'renamefar: submit failed'
    wait_marker "$menu_dir/$to" "renamefar: $label never wrote $to"
    menus_expect renameState ".index == -1 and (.pending | not) and (.loading | not) and .cursorName == \"$to\" and .cursor == $want" "$mode $label puts the cursor on $to at row $want"
    rename_design_still
    state=$(ipc providerState) || fail "renamefar: $label: cursor observation failed"
    menus_equal "$mode $label cursor path is the new name" "$menu_dir/$to" "$(jq -er .cursorPath <<< "$state")"
    menus_equal "$mode $label selects exactly the renamed row" "[$want]" "$(jq -c .selected <<< "$state")"
    menus_equal "$mode $label selected path is the renamed file" "[\"$menu_dir/$to\"]" "$(jq -c .selectedPaths <<< "$state")"
    rename_far_whole "$mode $label" "$want"
    menus_shot "rename-$mode-$label"
}

# A deep file renamed past the end and back, then another renamed to the top and back: each commit lands where the file sorted.
rename_design_far() {
    local mode="$1" total name row rename_far_name
    total=$(ipc total)
    # Row 300 sits past the first window and 1201 well past the one held around it.
    rename_far_deepen 300
    name="$rename_far_name"
    [[ "$name" =~ ^f([0-9]{4})\.txt$ ]] || fail "renamefar: the deep cursor row is $name, not a fixture file"
    row=$((rename_far_first_file_row + 10#${BASH_REMATCH[1]}))
    rename_far_commit far-down "$name" zzz-far.txt "$((total - 1))"
    rename_far_commit far-back zzz-far.txt "$name" "$row"
    rename_far_deepen 900
    name="$rename_far_name"
    [[ "$name" =~ ^f([0-9]{4})\.txt$ ]] || fail "renamefar: the deep cursor row is $name, not a fixture file"
    row=$((rename_far_first_file_row + 10#${BASH_REMATCH[1]}))
    rename_far_commit far-top "$name" 0000-far.txt 0
    rename_far_commit far-return 0000-far.txt "$name" "$row"
    wait_listing "$total"
}

case_renamefar() { case_renamedesign far; }
