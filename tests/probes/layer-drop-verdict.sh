#!/bin/bash
# Verdict helpers for the Bottom-layer drop probe, shared by the live probe and
# the headless scan. Pure string logic only, so tests/xwtab-scan.sh can drive
# every arm with fabricated input: no hyprctl, no qs, no process table here.
# The probe supplies the live readers around these; the scan stubs them.

# Pids in AFTER not in BEFORE, normalised numeric sort deduped, no edge space.
layerdrop_torn_pids() {
    local before="${1:-}" after="${2:-}" pid
    for pid in $after; do
        case " $before " in *" $pid "*) ;; *) printf '%s\n' "$pid";; esac
    done | sort -n -u | tr '\n' ' ' | sed 's/ *$//'
}

# 0 when the probe's own Bottom panel took the drop, read off its log file.
layerdrop_panel_hit() {
    grep -q PANEL-DROP "${1:-/dev/null}" 2>/dev/null
}

# 0 when HAVE is the lifted folder WANT, both from the same qs ipc path reader.
layerdrop_path_matches() {
    [[ -n "${1:-}" && "${1:-}" == "${2:-}" ]]
}

# 0 when any pid in TORN reads as WANT through PATHS_TSV ("pid<TAB>path" lines).
layerdrop_any_on_path() {
    local torn="$1" want="$2" paths_tsv="$3" pid line p
    [[ -n "$want" ]] || return 1
    [[ -n "$torn" ]] || return 1
    for pid in $torn; do
        p=""
        while IFS= read -r line; do
            [[ "${line%%$'\t'*}" == "$pid" ]] || continue
            p="${line#*$'\t'}"
            break
        done <<< "$paths_tsv"
        layerdrop_path_matches "$p" "$want" && return 0
    done
    return 1
}
