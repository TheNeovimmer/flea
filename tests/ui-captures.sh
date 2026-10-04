# Board capture cases (outside the default wanted list); tests/ui.sh supplies fixture, helpers and shots.

# Resize floats the owned window exact, the permissions_viewport idiom, so sizes are set not assumed.
cap_resize() {
    local target_width="$1" target_height="$2"
    local client address result wx wy width height end=$((SECONDS + 20))
    client=$(hyprctl clients -j | jq -ec --argjson pid "$(flea_pid)" '.[] | select(.pid == $pid)') \
        || fail "captures: owned window unavailable for resize to ${target_width}x${target_height}"
    address=$(jq -er '.address' <<< "$client") || fail "captures: owned window has no address"
    [[ "$address" =~ ^0x[0-9a-fA-F]+$ ]] || fail "captures: invalid owned window address $address"
    if ! jq -e '.floating' <<< "$client" >/dev/null; then
        omarchy-drive window float "$address" >/dev/null || fail "captures: owned window could not float"
    fi
    result=$(hypr_window_resize "$address" "$target_width" "$target_height" 2>&1) \
        || fail "captures: compositor refused resize to ${target_width}x${target_height}: $result"
    omarchy-drive window center "$address" >/dev/null || fail "captures: owned window could not center"
    while (( SECONDS < end )); do
        read -r wx wy width height < <(window_box) || fail "captures: native window coordinates unavailable"
        [[ "$width" == "$target_width" && "$height" == "$target_height" ]] && return 0
        sleep 0.05
    done
    fail "captures: viewport did not reach ${target_width}x${target_height}, it is ${width}x${height}"
}

# Tabs040: three tabs with one held mid-drag, then Settings View Opening on Last folder.
# Board specimens: the 900x541 tab-drag window, and the Opening excerpt with the Last
# folder hint, New tabs open in, Open items with and Click a selected name to rename.
case_cap_tabs() {
    local dir="$fixture_root/cap-tabs"
    sandbox_scratch "$dir"
    mkdir -p "$dir/alpha" "$dir/beta" "$dir/gamma"
    seed_ui_state "$fixture_root/cap-tabs-state" '{"keys":"default","view":"list"}'
    launch "$dir"
    wait_listing 3
    cap_resize 900 541
    key t >/dev/null
    settle
    key t >/dev/null
    settle
    [[ "$(ipc tabCount)" == "3" ]] || fail "cap_tabs: t twice did not make 3 tabs, count=$(ipc tabCount)"
    click_tab 0
    seek_row_named "alpha" || fail "cap_tabs: could not find alpha"
    key -k Return >/dev/null
    wait_path "$dir/alpha"
    click_tab 1
    seek_row_named "beta" || fail "cap_tabs: could not find beta"
    key -k Return >/dev/null
    wait_path "$dir/beta"
    click_tab 2
    seek_row_named "gamma" || fail "cap_tabs: could not find gamma"
    key -k Return >/dev/null
    wait_path "$dir/gamma"
    [[ "$(ipc tabLabels)" == "alpha|beta|gamma" ]] || fail "cap_tabs: tabs label [$(ipc tabLabels)], not alpha|beta|gamma"
    local c0x c0y c1x c1y c2x c2y w
    read -r c0x c0y <<< "$(ipc tabCentre 0)"
    read -r c1x c1y <<< "$(ipc tabCentre 1)"
    read -r c2x c2y <<< "$(ipc tabCentre 2)"
    [[ -n "$c1y" && -n "$c2y" ]] || fail "cap_tabs: a tab has no centre"
    w=$((c1x - c0x))
    (( w > 0 )) || fail "cap_tabs: tab centres do not step right [$c0x,$c1x,$c2x]"
    # tabdrag_to presses, moves, shots while held, then releases: the held shot is the specimen.
    tabdrag_to "$c1x" "$c1y" "$((c2x + w / 2 + 3))" "$c2y" cap-tabs-drag-held
    [[ "$(ipc tabLabels)" == "alpha|gamma|beta" ]] || fail "cap_tabs: drag labelled [$(ipc tabLabels)], not alpha|gamma|beta"
    settings_open_key
    settle
    settings_section view
    settings_focus_row startIn
    key l >/dev/null
    settle
    [[ "$(ipc settingsRows)" == *"Last folder reopens every tab you had."* ]] \
        || fail "cap_tabs: Last folder drew no tab hint, got $(ipc settingsRows)"
    [[ "$(ipc settingsRows)" == *"New tabs open in"* ]] \
        || fail "cap_tabs: Opening drew no New tabs row, got $(ipc settingsRows)"
    [[ "$(ipc settingsRows)" == *"Open items with"* ]] \
        || fail "cap_tabs: Opening drew no Open items row, got $(ipc settingsRows)"
    [[ "$(ipc settingsRows)" == *"Click a selected name to rename"* ]] \
        || fail "cap_tabs: Opening drew no click-rename row, got $(ipc settingsRows)"
    shot cap-tabs-opening-last-folder
    key -k Escape >/dev/null
    settle
    printf 'CAP_TABS drag=held labels=%s hint=shown\n' "$(ipc tabLabels)"
    kill_flea
}

# ClickAndRefresh: a slow-click rename as it opens, then Opening on Single click where
# Click a selected name to rename greys. Board specimen: the stem selected, ".md" muted.
case_cap_click() {
    local dir="$fixture_root/cap-click"
    sandbox_scratch "$dir"
    printf 'bench notes\n' > "$dir/field-bench-notes.md"
    : > "$dir/a.txt"
    : > "$dir/b.txt"
    seed_ui_state "$fixture_root/cap-click-state" '{"keys":"default","view":"list","openMode":"double","clickRename":true}'
    launch "$dir"
    wait_listing 3
    seek_row_named "field-bench-notes.md" || fail "cap_click: could not find field-bench-notes.md"
    local idx
    idx=$(row_index_of "field-bench-notes.md")
    click_row_name "$idx" left
    settle
    # A second click after the double-click interval starts rename; inside it opens instead.
    sleep 0.7
    click_row_name "$idx" left
    settle
    local waited
    for waited in $(seq 1 100); do
        [[ "$(ipc renameEditorLive)" == "true" ]] && break
        sleep 0.05
    done
    [[ "$(ipc renameEditorLive)" == "true" ]] || fail "cap_click: the slow click never opened rename"
    [[ "$(ipc renameEditorText)" == "field-bench-notes.md" ]] \
        || fail "cap_click: rename holds '$(ipc renameEditorText)', not field-bench-notes.md"
    [[ "$(ipc renameState | jq -r .selectedText)" == "field-bench-notes" ]] \
        || fail "cap_click: rename selects '$(ipc renameState | jq -r .selectedText)', not the stem"
    shot cap-click-rename-slow
    key -k Escape >/dev/null
    settle
    settings_open_key
    settle
    settings_section view
    settings_focus_row openMode
    key l >/dev/null
    settle
    [[ "$(ipc settingsModel | jq -er '[.[] | select(.id == "openMode")][0].value')" == *"Single"* ]] \
        || fail "cap_click: Open items with never reached Single click"
    [[ "$(ipc settingsModel | jq -er '[.[] | select(.id == "clickRename")][0].available')" == "false" ]] \
        || fail "cap_click: Click a selected name to rename never greyed under Single click"
    shot cap-click-opening-single
    key -k Escape >/dev/null
    settle
    printf 'CAP_CLICK rename=stem-selected single=greyed\n'
    kill_flea
}

# KeyboardFlows "View, Cursor at defaults": the Cursor group with both rows off.
case_cap_cursor() {
    local dir="$fixture_root/cap-cursor"
    sandbox_scratch "$dir"
    : > "$dir/a.txt"
    : > "$dir/b.txt"
    seed_ui_state "$fixture_root/cap-cursor-state" '{"keys":"default","view":"list","wrapAtEnds":false,"escapeUp":false}'
    launch "$dir"
    wait_listing 2
    settings_open_key
    settle
    settings_section view
    [[ "$(ipc settingsRows)" == *"Wrap at list ends"* ]] \
        || fail "cap_cursor: View drew no Wrap at list ends, got $(ipc settingsRows)"
    [[ "$(ipc settingsRows)" == *"Escape goes up a folder"* ]] \
        || fail "cap_cursor: View drew no Escape row, got $(ipc settingsRows)"
    [[ "$(ipc settingsModel | jq -er '[.[] | select(.id == "wrapAtEnds")][0].on')" == "false" ]] \
        || fail "cap_cursor: Wrap at list ends is not off"
    [[ "$(ipc settingsModel | jq -er '[.[] | select(.id == "escapeUp")][0].on')" == "false" ]] \
        || fail "cap_cursor: Escape goes up a folder is not off"
    shot cap-cursor-defaults
    key -k Escape >/dev/null
    settle
    printf 'CAP_CURSOR wrap=off escape=off\n'
    kill_flea
}

# MenuAdditions040: the file menu with the Copy as flyout open, Paste as once the
# clipboard holds a file, the symlink menu with Show original, the background menu at
# defaults, and Settings Menus listing the new rows. Key hints on throughout.
case_cap_menus() {
    local dir="$fixture_root/cap-menus"
    sandbox_scratch "$dir"
    printf 'target\n' > "$dir/target.txt"
    ln -s target.txt "$dir/link.txt" || fail "cap_menus: the symlink fixture could not be made"
    seed_ui_state "$fixture_root/cap-menus-state" '{"keys":"default","view":"list","keyHints":true,"menu":{"hidden":["delete","openTerminal","moveto","copyto","properties","permissions","invertSelection"]}}'
    launch "$dir"
    wait_listing 2
    click_row "$(row_index_of target.txt)" right
    settle
    [[ "$(ipc contextMenuVisible)" == "true" ]] || fail "cap_menus: the file menu never opened"
    [[ "|$(ipc contextMenuEntries)|" == *"|Copy as|"* ]] \
        || fail "cap_menus: the file menu offers no Copy as, got $(ipc contextMenuEntries)"
    menu_seek "Copy as"
    key -k Right >/dev/null
    settle
    [[ "$(ipc contextMenuSubmenuEntries)" == *"Path"* ]] \
        || fail "cap_menus: the Copy as flyout offers $(ipc contextMenuSubmenuEntries)"
    shot cap-menus-file-copyas
    key -k Escape >/dev/null
    settle
    key -k Escape >/dev/null
    settle
    [[ "$(ipc contextMenuVisible)" == "false" ]] || fail "cap_menus: the Copy as menu stayed open"
    click_row "$(row_index_of target.txt)" left
    settle
    key y >/dev/null
    settle
    [[ "$(ipc keyDeliveryState | jq -er '.clipboard.paths | length')" == "1" ]] \
        || fail "cap_menus: y put no file on the clipboard"
    click_row "$(row_index_of target.txt)" right
    settle
    menu_seek "Paste as"
    key -k Right >/dev/null
    settle
    [[ "$(ipc contextMenuSubmenuEntries)" == *"Link"* ]] \
        || fail "cap_menus: the Paste as flyout offers $(ipc contextMenuSubmenuEntries)"
    shot cap-menus-file-pasteas
    key -k Escape >/dev/null
    settle
    key -k Escape >/dev/null
    settle
    [[ "$(ipc contextMenuVisible)" == "false" ]] || fail "cap_menus: the Paste as menu stayed open"
    click_row "$(row_index_of link.txt)" right
    settle
    [[ "|$(ipc contextMenuEntries)|" == *"|Show original|"* ]] \
        || fail "cap_menus: the symlink menu offers no Show original, got $(ipc contextMenuEntries)"
    shot cap-menus-symlink
    key -k Escape >/dev/null
    settle
    kill_flea
    seed_ui_state "$fixture_root/cap-menus-background-state" '{"keys":"default","view":"list","keyHints":true,"menu":{"hidden":["delete","openTerminal","placeMenu","runScript","moveto","copyto","properties","permissions","copyAs","pasteAs","extThumbs"]}}'
    launch "$dir"
    wait_listing 2
    click_row "$(row_index_of target.txt)" left
    settle
    local background_selection_count
    background_selection_count=$(ipc selectionCount)
    [[ "$background_selection_count" == "1" ]] \
        || fail "cap_menus: background specimen needs one selected row, got $background_selection_count"
    key y >/dev/null
    settle
    click_background
    settle
    [[ "$(ipc contextMenuVisible)" == "true" ]] || fail "cap_menus: the background menu never opened"
    local background_labels='New Folder|New File|-|Paste|Select all|Invert selection|-|Open in terminal|Add to Favorites|-|Sort by|Show hidden files|-|Settings'
    [[ "$(ipc contextMenuEntries)" == "$background_labels" ]] \
        || fail "cap_menus: background specimen drew $(ipc contextMenuEntries), want $background_labels"
    shot cap-menus-background
    key -k Escape >/dev/null
    settle
    kill_flea
    seed_ui_state "$fixture_root/cap-menus-state" '{"keys":"default","view":"list","keyHints":true,"menu":{"hidden":["delete","openTerminal","moveto","copyto","properties","permissions","invertSelection"]}}'
    launch "$dir"
    wait_listing 2
    settings_open_key
    settle
    settings_section menus
    [[ "$(ipc settingsRows)" == *"Copy as"* ]] || fail "cap_menus: Menus lists no Copy as"
    [[ "$(ipc settingsRows)" == *"Paste as"* ]] || fail "cap_menus: Menus lists no Paste as"
    [[ "$(ipc settingsRows)" == *"Invert selection"* ]] || fail "cap_menus: Menus lists no Invert selection"
    [[ "$(ipc settingsRows)" == *"Permissions"* ]] || fail "cap_menus: Menus lists no Permissions"
    shot cap-menus-settings
    key -k Escape >/dev/null
    settle
    printf 'CAP_MENUS copyas=ok pasteas=ok symlink=ok background=ok settings=ok\n'
    kill_flea
}

# Permissions040: Tab or Shift+Tab until the dialog's focused control has this name, within the whole ring of controls.
cap_permissions_focus() {
    local want="$1" direction="$2" state tabs
    local focus_limit=16
    for ((tabs = 0; tabs <= focus_limit; tabs++)); do
        state=$(ipc permissionsState) || fail "cap_permissions: the permissions reader failed"
        [[ "$(jq -r --arg want "$want" '[.controls[] | select(.focused and .name == $want)] | length' <<< "$state")" == "1" ]] && return 0
        if [[ "$direction" == back ]]; then key -M shift -k Tab -m shift >/dev/null; else key -k Tab >/dev/null; fi
        settle
    done
    fail "cap_permissions: Tab never reached $want, last $state"
}

# Permissions040: a focused check box in the state its bit holds, off, on or mixed ("some" in the control state).
cap_permissions_box() {
    local name="$1" value="$2" shot_name="$3"
    cap_permissions_focus "$name" forward
    [[ "$(ipc permissionsState | jq -r --arg want "$name" '[.controls[] | select(.name == $want)][0].value')" == "$value" ]] \
        || fail "cap_permissions: $name does not hold $value in the fixture"
    shot "$shot_name"
}

# Permissions040 pointer states: a hover or a held press proven through ipc, the press let go off the control so nothing acts.
cap_permissions_pointer() {
    local name="$1" mode="$2" shot_name="$3" centre cx cy wx wy ww wh
    local settle_limit_s=5 away_px=150 nudge_px=1
    centre=$(ipc permissionsState | jq -er --arg name "$name" '.controls[] | select(.name == $name and .visible) | .centre') \
        || fail "cap_permissions: no visible $name control to point at"
    read -r cx cy <<< "$centre"
    read -r wx wy ww wh < <(window_box) || fail "cap_permissions: native window coordinates unavailable"
    assert_focus
    # Two moves so the first lands as the resting point, then a seat nudge there and back, since Hyprland's cursor move sends Qt no pointer frame.
    omarchy-drive move "$((wx + cx - nudge_px * 6))" "$((wy + cy))" >/dev/null || fail "cap_permissions: pointer approach to $name failed"
    omarchy-drive move "$((wx + cx))" "$((wy + cy))" >/dev/null || fail "cap_permissions: pointer move onto $name failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x "$nudge_px" -y 0 >/dev/null 2>&1 || fail "cap_permissions: pointer nudge failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x "-$nudge_px" -y 0 >/dev/null 2>&1 || fail "cap_permissions: pointer nudge back failed"
    cap_permissions_wait_pointer "$name" hovered true "$settle_limit_s"
    if [[ "$mode" == hover ]]; then
        settle
        shot "$shot_name"
        return 0
    fi
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click 0x40 >/dev/null 2>&1 || fail "cap_permissions: pointer press on $name failed"
    cap_permissions_wait_pointer "$name" pressed true "$settle_limit_s"
    settle
    shot "$shot_name"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 0 -y "-$away_px" >/dev/null 2>&1 || fail "cap_permissions: pointer move off $name failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click 0x80 >/dev/null 2>&1 || fail "cap_permissions: pointer release failed"
    cap_permissions_wait_pointer "$name" pressed false "$settle_limit_s"
}
cap_permissions_wait_pointer() {
    local name="$1" field="$2" want="$3" limit="$4" end state
    end=$((SECONDS + limit))
    while (( SECONDS < end )); do
        state=$(ipc permissionsState) || fail "cap_permissions: the permissions reader failed"
        [[ "$(jq -r --arg name "$name" --arg field "$field" '[.controls[] | select(.name == $name)][0][$field]' <<< "$state")" == "$want" ]] && return 0
        sleep 0.05
    done
    fail "cap_permissions: $name never reported $field=$want, last $state"
}
# One pointer click on a grid box, asserted to land on the value the cycle names (mixed, on, off, mixed).
cap_permissions_click_box() {
    local name="$1" want="$2" shot_name="$3" centre end
    local settle_limit_s=5
    centre=$(ipc permissionsState | jq -er --arg name "$name" '.controls[] | select(.name == $name and .visible) | .centre') \
        || fail "cap_permissions: no visible $name box to click"
    permissions_click_at "$centre"
    end=$((SECONDS + settle_limit_s))
    while (( SECONDS < end )); do
        [[ "$(ipc permissionsState | jq -r --arg name "$name" '[.controls[] | select(.name == $name)][0].value')" == "$want" ]] && break
        sleep 0.05
    done
    [[ "$(ipc permissionsState | jq -r --arg name "$name" '[.controls[] | select(.name == $name)][0].value')" == "$want" ]] \
        || fail "cap_permissions: $name did not reach $want after the click"
    # The click leaves the pointer over the box, so the shot is the box as it reads after that click.
    settle
    shot "$shot_name"
}
permissions_click_at() {
    local centre="$1" cx cy wx wy ww wh
    read -r cx cy <<< "$centre"
    [[ "$cx" =~ ^[0-9]+$ && "$cy" =~ ^[0-9]+$ ]] || fail "cap_permissions: control has no centre"
    read -r wx wy ww wh < <(window_box) || fail "cap_permissions: native window coordinates unavailable"
    assert_focus
    omarchy-drive click "$((wx + cx))" "$((wy + cy))" left >/dev/null || fail "cap_permissions: pointer click failed"
}
# Sample output: live, disabled or absent; a live entry carries no disabled key at all, so a missing one reads live.
cap_permissions_makeexec_state() {
    ipc menuState | jq -r '[.entries[] | select(.action == "makeExecutable")][0] | if . == null then "absent" elif (.disabled // false) then "disabled" else "live" end'
}

# Permissions040 callout 3: the file menu on a shebang script at 0644 with Permissions unhidden offers Make executable beside its glyph.
cap_permissions_menu_specimen() {
    local entries="" end
    local settle_limit_s=15
    click_row 0 left
    settle
    click_row 4 right
    end=$((SECONDS + settle_limit_s))
    # The row goes live when the two-byte shebang read answers, so the wait is on the live row, not on its label.
    while (( SECONDS < end )); do
        entries=$(ipc contextMenuEntries)
        [[ "$entries" == *"Make executable"* && "$(cap_permissions_makeexec_state)" == "live" ]] && break
        sleep 0.1
    done
    [[ "$entries" == *"Make executable"* && "$entries" == *"Permissions"* ]] \
        || fail "cap_permissions: the shebang script's menu lacks Make executable or Permissions, got $entries"
    [[ "$(cap_permissions_makeexec_state)" == "live" ]] \
        || fail "cap_permissions: Make executable is not live on the shebang script, it reads $(cap_permissions_makeexec_state)"
    shot cap-permissions-makeexec-menu
    key -k Escape >/dev/null
    settle
}
# Permissions040: the single-item card on a setuid file keeps its values and dims every box to the disabled opacity.
cap_permissions_special_single() {
    local state
    click_row 0 left
    settle
    cap_permissions_open 5
    state=$(ipc permissionsState) || fail "cap_permissions: the permissions reader failed on the setuid file"
    [[ "$(jq -r '.displayedError' <<< "$state")" == "Read-only: setuid bit is present." ]] \
        || fail "cap_permissions: the setuid card names no reason, state $state"
    [[ "$(jq -r '[.controls[] | select(.bit != null and .enabled == false)] | length' <<< "$state")" == "9" ]] \
        || fail "cap_permissions: the setuid card leaves a box enabled, state $state"
    [[ "$(jq -r '[.controls[] | select(.bit != null and .value == "on")] | length' <<< "$state")" == "4" ]] \
        || fail "cap_permissions: the setuid card lost its 4644 values, state $state"
    shot cap-permissions-special-single
    key -k Escape >/dev/null
    settle
}

# Permissions040: from the file menu on the cursor row (right click), open the card and wait for it to settle idle.
cap_permissions_open() {
    local row="$1" end state
    local settle_limit_s=15
    click_row "$row" right
    settle
    [[ "$(ipc contextMenuVisible)" == "true" ]] || fail "cap_permissions: the menu on row $row never opened"
    [[ "$(ipc menuState | jq -er '[.entries[] | select(.action == "permissions")][0].disabled')" == "false" ]] \
        || fail "cap_permissions: Permissions is not live on row $row"
    menu_seek "Permissions"
    key -k Return >/dev/null
    end=$((SECONDS + settle_limit_s))
    while (( SECONDS < end )); do
        state=$(ipc permissionsState) || fail "cap_permissions: the permissions reader failed"
        [[ "$(jq -r .opened <<< "$state")" == "true" && "$(jq -r .busy <<< "$state")" == "false" ]] && return 0
        sleep 0.05
    done
    fail "cap_permissions: Permissions never settled open and idle, last $state"
}

# Permissions040: the several-items card with a focused check box in each state, the single-item card with an invalid octal, the errored symlink row and the note.
case_cap_permissions() {
    local dir="$fixture_root/cap-permissions" state
    sandbox_scratch "$dir"
    printf 'one\n' > "$dir/a.txt"
    printf 'two\n' > "$dir/b.txt"
    printf 'three\n' > "$dir/c.txt"
    printf 'special\n' > "$dir/special.txt"
    printf '#!/bin/sh\necho run\n' > "$dir/run.sh"
    chmod 0644 "$dir/run.sh" || fail "cap_permissions: the shebang fixture mode failed"
    ln -s a.txt "$dir/link.txt" || fail "cap_permissions: the symlink fixture failed"
    chmod 0644 "$dir/a.txt" || fail "cap_permissions: the 644 fixture mode failed"
    chmod 0600 "$dir/b.txt" || fail "cap_permissions: the 600 fixture mode failed"
    chmod 0755 "$dir/c.txt" || fail "cap_permissions: the 755 fixture mode failed"
    chmod 4644 "$dir/special.txt" || fail "cap_permissions: the setuid fixture mode failed"
    seed_ui_state "$fixture_root/cap-permissions-state" '{"keys":"default","view":"list","menu":{"hidden":["delete","openTerminal","moveto","copyto","properties","copyAs","pasteAs","invertSelection"]}}'
    launch "$dir"
    wait_listing 6
    cap_resize 904 699
    click_row 0 left
    settle
    click_row 1 left --mods ctrl
    settle
    click_row 2 left --mods ctrl
    settle
    [[ "$(ipc selectionCount)" == "3" ]] || fail "cap_permissions: three ctrl clicks selected $(ipc selectionCount), not 3"
    cap_permissions_open 0
    shot cap-permissions-multi
    # Tab from Cancel runs Apply, Close, then the grid: Owner read is on, Owner execute mixed, Group write off.
    cap_permissions_box "Owner read" on cap-permissions-box-on
    cap_permissions_box "Owner execute" some cap-permissions-box-mixed
    cap_permissions_box "Group write" off cap-permissions-box-off
    cap_permissions_pointer "Owner read" hover cap-permissions-box-hover
    cap_permissions_pointer "Owner read" press cap-permissions-box-pressed
    # Mixed, one click on, a second click off: the Owner execute bit differs across the three files.
    cap_permissions_click_box "Owner execute" on cap-permissions-box-mixed-click1
    cap_permissions_click_box "Owner execute" off cap-permissions-box-mixed-click2
    key -k Escape >/dev/null
    settle
    click_row 0 left
    settle
    cap_permissions_open 0
    cap_permissions_focus Apply forward
    shot cap-permissions-apply-focus
    cap_permissions_focus Close forward
    shot cap-permissions-close-focus
    cap_permissions_focus Octal back
    shot cap-permissions-octal-focus
    key -M ctrl -k a -m ctrl -k 9 >/dev/null
    settle
    [[ "$(ipc permissionsState | jq -r '.displayedError | length')" != "0" ]] || fail "cap_permissions: an invalid octal drew no error"
    shot cap-permissions-octal-error
    cap_permissions_focus Cancel forward
    state=$(ipc permissionsState) || fail "cap_permissions: the permissions reader failed before the disabled-Apply shot"
    [[ "$(jq -r '[.controls[] | select(.name == "Apply")][0].enabled' <<< "$state")" == "false" ]] \
        || fail "cap_permissions: Apply is not disabled over the invalid octal, state $state"
    [[ "$(jq -r '.mode | test("9")' <<< "$state")" == "true" ]] \
        || fail "cap_permissions: the invalid octal left the field before the disabled-Apply shot, mode $(jq -r .mode <<< "$state")"
    shot cap-permissions-apply-disabled
    cap_permissions_pointer Cancel hover cap-permissions-cancel-hover
    cap_permissions_pointer Cancel press cap-permissions-cancel-pressed
    key -k Escape >/dev/null
    settle
    # Apply is live over a valid octal, so its hover and press are shot on a fresh card.
    click_row 0 left
    settle
    cap_permissions_open 0
    cap_permissions_pointer Apply hover cap-permissions-apply-hover
    cap_permissions_pointer Apply press cap-permissions-apply-pressed
    key -k Escape >/dev/null
    settle
    click_row 3 right
    settle
    [[ "$(ipc menuState | jq -er '[.entries[] | select(.action == "permissions")][0].disabled')" == "true" ]] \
        || fail "cap_permissions: Permissions is not the errored row on a symlink"
    shot cap-permissions-symlink-menu
    key -k Escape >/dev/null
    settle
    cap_permissions_menu_specimen
    cap_permissions_special_single
    click_row 0 left
    settle
    click_row 5 left --mods ctrl
    settle
    [[ "$(ipc selectionCount)" == "2" ]] || fail "cap_permissions: the setuid pair selected $(ipc selectionCount), not 2"
    cap_permissions_open 0
    [[ "$(ipc permissionsState | jq -r '.displayedError | length')" != "0" ]] || fail "cap_permissions: the setuid file drew no note for several items"
    shot cap-permissions-multi-note
    key -k Escape >/dev/null
    settle
    printf 'CAP_PERMISSIONS mixed=3rows boxes=on,mixed,off,hover,pressed,click1,click2 single=apply,octal,error,disabled,close,special,pointer symlink=errored note=setuid menu=makeexec\n'
    kill_flea
}

# Sidebar040: the rail with Recent switched on, Settings Places showing it, and a
# favourites reorder held mid-drag. The rail drag reuses tabdrag_to's uinput motion:
# press on one favourite centre, move to the other, shot while held, then release.
case_cap_sidebar() {
    local dir="$fixture_root/cap-sidebar"
    sandbox_scratch "$dir"
    mkdir -p "$dir/alpha" "$dir/beta"
    : > "$dir/note.txt"
    seed_ui_state "$fixture_root/cap-sidebar-state" "$(printf '{"keys":"default","view":"list","places":{"showRecent":true,"favourites":[{"label":"Alpha","path":"%s/alpha"},{"label":"Beta","path":"%s/beta"}]}}' "$dir" "$dir")"
    launch "$dir"
    wait_listing 3
    cap_resize 1120 543
    wait_rail_label "Recent"
    [[ "$(ipc railEntries | jq -er 'any(.[]; .label == "Recent")')" == "true" ]] \
        || fail "cap_sidebar: the rail carries no Recent row"
    shot cap-sidebar-recent
    settings_open_key
    settle
    settings_section places
    [[ "$(ipc settingsRows)" == *"Recent"* ]] || fail "cap_sidebar: Places lists no Recent row"
    shot cap-sidebar-places
    key -k Escape >/dev/null
    settle
    local alpha_index beta_index ax ay bx by before_alpha before_beta after_alpha after_beta
    alpha_index=$(rail_row_of "Alpha")
    beta_index=$(rail_row_of "Beta")
    (( alpha_index < beta_index )) || fail "cap_sidebar: favourites order is not Alpha then Beta"
    read -r ax ay <<< "$(ipc railRowCentre "$alpha_index")"
    read -r bx by <<< "$(ipc railRowCentre "$beta_index")"
    [[ -n "$ay" && -n "$by" ]] || fail "cap_sidebar: a favourite has no rail centre"
    before_alpha="$alpha_index"
    tabdrag_to "$ax" "$ay" "$bx" "$by" cap-sidebar-drag-held
    alpha_index=$(rail_row_of "Alpha")
    beta_index=$(rail_row_of "Beta")
    after_alpha="$alpha_index"
    after_beta="$beta_index"
    (( after_beta < after_alpha )) || fail "cap_sidebar: the held drag never reordered, Alpha at $after_alpha Beta at $after_beta (was $before_alpha)"
    printf 'CAP_SIDEBAR recent=on drag=held reorder=ok\n'
    kill_flea
}

# CommandPalette: rest, then the shipped perm specimen; tag belongs to 0.3.9.
case_cap_sheet() {
    local dir="$fixture_root/cap-sheet"
    local sheet_rows query="perm" end
    local clear_wait_s=10
    sandbox_scratch "$dir"
    : > "$dir/a.txt"
    : > "$dir/b.txt"
    seed_ui_state "$fixture_root/cap-sheet-state" '{"keys":"default","view":"list"}'
    launch "$dir"
    wait_listing 2
    key '?' >/dev/null
    omarchy-drive wait ipc -p "$flea_ui/boot" flea keymapSheetOpen true --timeout 10 >/dev/null \
        || fail "cap_sheet: ? opened no keymap sheet"
    [[ "$(ipc keymapSheetOpen)" == "true" ]] || fail "cap_sheet: ? opened no keymap sheet"
    [[ "$(ipc keymapQuery)" == "" ]] || fail "cap_sheet: the resting sheet carries query '$(ipc keymapQuery)'"
    shot cap-sheet-rest
    key p >/dev/null
    key e >/dev/null
    key r >/dev/null
    key m >/dev/null
    omarchy-drive wait ipc -p "$flea_ui/boot" flea keymapQuery perm --timeout 10 >/dev/null \
        || fail "cap_sheet: the query never reached perm, it is '$(ipc keymapQuery)'"
    [[ "$(ipc keymapQuery)" == "perm" ]] || fail "cap_sheet: the query is '$(ipc keymapQuery)', not perm"
    sheet_rows=$(ipc keymapSheetRows)
    grep -Fxq 'shift-delete delete permanently' <<< "$sheet_rows" \
        || fail "cap_sheet: the perm query lists no delete permanently row"
    shot cap-sheet-query
    key -k Escape >/dev/null
    end=$((SECONDS + clear_wait_s))
    while (( SECONDS < end )); do
        query=$(ipc keymapQuery) || fail "cap_sheet: keymapQuery failed after Escape"
        [[ "$query" == "" ]] && break
        settle
    done
    [[ "$query" == "" ]] || fail "cap_sheet: Escape did not clear the query, last value '$query'"
    printf 'CAP_SHEET rest=ok query=perm\n'
    kill_flea
}

# Aspect rule check for one matrix cell: drawn picture against ownsize, fit or fill.
matrix_check() {
    local label="$1" frame="$2" picture="$3" src="$4" mode="$5" inset="$6"
    python3 - "$label" "$frame" "$picture" "$src" "$mode" "$inset" <<'PYEOF' || fail "previewmatrix: $label drew outside its rule"
import sys
label, frame, picture, src, mode, inset = sys.argv[1:7]
inset = float(inset)
fx, fy, fw, fh = [float(v) for v in frame.split()]
px, py, pw, ph = [float(v) for v in picture.split()]
sw, sh = [float(v) for v in src.split()]
if mode == "ownsize":
    want_w, want_h = sw, sh
else:
    # Fit keeps own pixels and fill enlarges a small clip; both draw the aspect-fit of the box.
    scale = min((fw - inset) / sw, (fh - inset) / sh)
    want_w, want_h = sw * scale, sh * scale
assert abs(pw - want_w) <= 2, "width %s, rule wants %s" % (pw, want_w)
assert abs(ph - want_h) <= 2, "height %s, rule wants %s" % (ph, want_h)
assert abs(2 * px + pw - (2 * fx + fw)) <= 4, "not centred horizontally"
assert abs(2 * py + ph - (2 * fy + fh)) <= 4, "not centred vertically"
print("PREVIEWMATRIX %s frame=%sx%s drawn=%sx%s rule=%s ok" % (label, fw, fh, pw, ph, mode))
PYEOF
}

# A column picture that is decoded and on screen: the state, the shown mark and the ready frame.
# Sample input, previewSelectionState: {"view":"columns","index":2,"path":"/fixture/b-large.jpg"}.
matrix_wait_column() {
    local want="$1" file="$2" state path
    local end=$((SECONDS + 10))
    # Same-kind seeks land on the previous file's Ready frame first, so wait for this file's path.
    while (( SECONDS < end )); do
        path=$(ipc previewSelectionState | jq -r .path)
        [[ "$path" == *"$file" ]] && break
        sleep 0.1
    done
    [[ "$path" == *"$file" ]] \
        || fail "previewmatrix: the column still shows $path, not $file"
    end=$((SECONDS + 25))
    while (( SECONDS < end )); do
        state=$(ipc previewColumnState)
        [[ "$state" == "$want" && "$(ipc columnThumbShown)" == "true" ]] && break
        sleep 0.1
    done
    [[ "$state" == "$want" && "$(ipc columnThumbShown)" == "true" ]] \
        || fail "previewmatrix: the column shows $state, thumb shown $(ipc columnThumbShown), not $want"
    end=$((SECONDS + 10))
    while (( SECONDS < end )); do
        [[ "$(ipc columnFrameReady)" == "true" ]] && return 0
        sleep 0.1
    done
    fail "previewmatrix: the column frame never read Ready"
}

# Quick Look ownsize needs a surface larger than the source, or the rule misjudges on a small tile.
# Sample input, previewSurfaceRect: 240 151 2080 1137.
matrix_require_surface() {
    local min_width="$1" min_height="$2" rect sw sh
    rect=$(ipc previewSurfaceRect) || fail "previewmatrix: the overlay surface never reported"
    [[ "$rect" =~ ^-?[0-9]+\ -?[0-9]+\ [0-9]+\ [0-9]+$ ]] \
        || fail "previewmatrix: the overlay surface has no valid rectangle: $rect"
    read -r _ _ sw sh <<< "$rect"
    (( sw > min_width && sh > min_height )) \
        || fail "previewmatrix: surface ${sw}x${sh} cannot carry the ${min_width}x${min_height} ownsize cell"
}

matrix_click_play() {
    local cx cy wx wy
    read -r cx cy <<< "$(ipc columnPlayCentre)"
    [[ -n "$cy" ]] || fail "previewmatrix: the transport has no play centre to press"
    read -r wx wy _ww _wh < <(window_box) || fail "native window coordinates unavailable"
    omarchy-drive click "$((cx + wx))" "$((cy + wy))" left >/dev/null
}

# Matrix: images draw min(own pixels, aspect-fit), never enlarged; a small clip poster and player fill.
case_previewmatrix() {
    command -v ffmpeg >/dev/null || fail "ffmpeg is missing, so the clip fixtures cannot be built"
    command -v magick >/dev/null || fail "magick is missing, so the image fixtures cannot be built"
    local dir="$fixture_root/previewmatrix"
    sandbox_scratch "$dir"
    magick -size 64x48 xc:'#7aa2f7' "$dir/a-small.png" \
        || fail "previewmatrix: the 64x48 fixture failed"
    magick -size 1920x1080 xc:'#7aa2f7' "$dir/b-large.jpg" \
        || fail "previewmatrix: the 1920x1080 fixture failed"
    magick -size 1080x1920 xc:'#e0af68' "$dir/c-portrait.png" \
        || fail "previewmatrix: the portrait fixture failed"
    # Fifteen seconds: an ipc round trip costs 190 to 565 ms, so a short clip starves the play poll.
    ffmpeg -y -f lavfi -i "testsrc=duration=15:size=64x64:rate=10" "$dir/d-tiny.mp4" >/dev/null 2>&1 \
        || fail "previewmatrix: ffmpeg could not make d-tiny.mp4"
    ffmpeg -y -f lavfi -i "testsrc=duration=15:size=1920x1080:rate=10" "$dir/e-big.mp4" >/dev/null 2>&1 \
        || fail "previewmatrix: ffmpeg could not make e-big.mp4"

    seed_ui_state "$fixture_root/previewmatrix-state" '{"keys":"default","view":"columns"}'
    launch "$dir"
    wait_listing 5
    settle
    [[ "$(ipc viewMode)" == columns ]] || fail "previewmatrix: the fixture did not open its columns view"
    # Pin the window: the Quick Look ownsize cells below need a surface larger than 1920x1080.
    local matrix_width=2560 matrix_height=1440
    cap_resize "$matrix_width" "$matrix_height"

    # Columns, one row per class: images draw min(own pixels, fit) and video fills either way.
    seek_row_named "a-small.png"
    matrix_wait_column image a-small.png
    matrix_check "columns a-small.png" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "64 48" ownsize 2
    shot matrix-col-a-small
    seek_row_named "b-large.jpg"
    matrix_wait_column image b-large.jpg
    matrix_check "columns b-large.jpg" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "1920 1080" fit 2
    shot matrix-col-b-large
    seek_row_named "c-portrait.png"
    matrix_wait_column image c-portrait.png
    matrix_check "columns c-portrait.png" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "1080 1920" fit 2
    shot matrix-col-c-portrait
    seek_row_named "d-tiny.mp4"
    matrix_wait_column video d-tiny.mp4
    matrix_check "columns d-tiny.mp4 poster" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "64 64" fill 2
    shot matrix-col-d-poster
    seek_row_named "e-big.mp4"
    matrix_wait_column video e-big.mp4
    matrix_check "columns e-big.mp4 poster" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "1920 1080" fill 2
    shot matrix-col-e-poster

    # The column player, on the small and the large clip: the content rect fills the same way.
    seek_row_named "d-tiny.mp4"
    matrix_wait_column video d-tiny.mp4
    matrix_click_play
    local end=$((SECONDS + 10))
    while (( SECONDS < end )); do
        [[ "$(ipc columnMediaPlaying)" == "true" ]] && break
        sleep 0.1
    done
    [[ "$(ipc columnMediaPlaying)" == "true" ]] || fail "previewmatrix: the column player never played d-tiny.mp4"
    matrix_check "columns d-tiny.mp4 player" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "64 64" fill 2
    shot matrix-col-d-player
    seek_row_named "e-big.mp4"
    matrix_wait_column video e-big.mp4
    matrix_click_play
    end=$((SECONDS + 10))
    while (( SECONDS < end )); do
        [[ "$(ipc columnMediaPlaying)" == "true" ]] && break
        sleep 0.1
    done
    [[ "$(ipc columnMediaPlaying)" == "true" ]] || fail "previewmatrix: the column player never played e-big.mp4"
    matrix_check "columns e-big.mp4 player" "$(ipc columnFrameRect)" "$(ipc columnPictureRect)" "1920 1080" fill 2
    shot matrix-col-e-player

    # Quick Look on the pinned surface: small and 1920x1080 hold own size, portrait takes fit, video fills.
    seek_row_named "a-small.png"
    matrix_wait_column image a-small.png
    key -k space >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "true" && "$(ipc previewKind)" == "image" ]] \
        || fail "previewmatrix: Space never opened the image overlay"
    matrix_check "quicklook a-small.png" "$(ipc previewSurfaceRect)" "$(ipc previewPictureRect)" "64 48" ownsize 0
    shot matrix-look-a-small
    key -k Escape >/dev/null
    settle
    seek_row_named "b-large.jpg"
    matrix_wait_column image b-large.jpg
    key -k space >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "true" && "$(ipc previewKind)" == "image" ]] \
        || fail "previewmatrix: Space never opened the large overlay"
    matrix_require_surface 1920 1080
    matrix_check "quicklook b-large.jpg" "$(ipc previewSurfaceRect)" "$(ipc previewPictureRect)" "1920 1080" ownsize 0
    shot matrix-look-b-large
    key -k Escape >/dev/null
    settle
    seek_row_named "c-portrait.png"
    matrix_wait_column image c-portrait.png
    key -k space >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "true" && "$(ipc previewKind)" == "image" ]] \
        || fail "previewmatrix: Space never opened the portrait overlay"
    matrix_check "quicklook c-portrait.png" "$(ipc previewSurfaceRect)" "$(ipc previewPictureRect)" "1080 1920" fit 0
    shot matrix-look-c-portrait
    key -k Escape >/dev/null
    settle
    seek_row_named "d-tiny.mp4"
    matrix_wait_column video d-tiny.mp4
    key -k space >/dev/null
    wait_preview_state playing
    matrix_check "quicklook d-tiny.mp4" "$(ipc previewSurfaceRect)" "$(ipc previewPictureRect)" "64 64" fill 0
    shot matrix-look-d-player
    key -k Escape >/dev/null
    settle
    seek_row_named "e-big.mp4"
    matrix_wait_column video e-big.mp4
    key -k space >/dev/null
    wait_preview_state playing
    matrix_check "quicklook e-big.mp4" "$(ipc previewSurfaceRect)" "$(ipc previewPictureRect)" "1920 1080" fill 0
    shot matrix-look-e-player
    key -k Escape >/dev/null
    settle

    # One contact sheet for the whole matrix, labelled by file name, beside the shot evidence.
    magick montage -label '%f' "$evidence_dir"/matrix-*.png -tile 4x -geometry 320x240+4+4 \
        "$evidence_dir/previewmatrix-sheet.png" \
        || fail "previewmatrix: the contact sheet failed"
    printf 'PREVIEWMATRIX cells=12 ok=12\n'
    printf 'PREVIEWMATRIX_SHEET %s\n' "$evidence_dir/previewmatrix-sheet.png"
    kill_flea
}
