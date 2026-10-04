#!/usr/bin/env bash
# Contact sheets for the Markdown spec run: Flea's view offscreen at body 14 beside the spec's HTML in chromium, one PNG per section group.
# Usage: [MDSPEC_SHEET_LIMIT=N] tools/mdspec-sheets/run.sh; the PNGs land in .superpowers/038-out/specsheets/. Needs the qs-suite helper and /usr/bin/chromium.
set -u
cd "$(dirname "$0")/../.." || exit 1
root=$PWD
work=$root/.superpowers/tmp/specsheets
out=$root/.superpowers/038-out/specsheets
suite_helper=/home/gm/flea-ops/claude/038/bin/qs-suite.sh
for tool in python3 /usr/bin/chromium; do
    command -v "$tool" >/dev/null || { echo "mdspec-sheets: $tool is missing"; exit 1; }
done
[ -f "$suite_helper" ] || { echo "mdspec-sheets: $suite_helper is missing"; exit 1; }
mkdir -p "$work" "$out" || exit 1
# The captures need qs, which only the container image carries; the suite copies each PNG to qs-out.
MDSPEC_SHEET_LIMIT=${MDSPEC_SHEET_LIMIT:-0} bash "$suite_helper" "$root" mdspec-shots || exit 1
mkdir -p "$work/shots" && cp -f "$root/.superpowers/qs-out/latest/mdspec-shots/"*.png "$work/shots/" || exit 1
python3 tools/mdspec-sheets/sheets.py manifest "$work" "${MDSPEC_SHEET_LIMIT:-0}" || exit 1
python3 tools/mdspec-sheets/sheets.py sheets "$work" "$out"
