#!/bin/bash
# Normalised pid set for the xwtab tear-off count, shared by tests/ui.sh and tests/xwtab-scan.sh: no empty member, sorted, unique, trimmed.
xwtab_norm_set() {
    printf '%s' "${1:-}" | tr -s '[:space:]' '\n' | grep -v '^$' | sort -n -u | tr '\n' ' ' | sed 's/ *$//'
}
