#!/usr/bin/env bash
# Display-free registration, IPC-contract and failed-capture checks for the native sweep cases.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
[[ "$scratch" == /*/* ]] || { printf 'FAIL: scratch path is not absolute\n' >&2; exit 1; }
trap 'rm -rf -- "$scratch"' EXIT
cd "$repo"
bash -n tests/ui.sh tests/ui-captures-sweep.sh
python3 - <<'PY'
import ast, pathlib, re, tomllib
root = pathlib.Path.cwd()
driver = (root / "tests/ui.sh").read_text()
capture = (root / "tests/ui-captures-sweep.sh").read_text()
# Sample input: . "$repo/tests/ui-captures-sweep.sh"
sources = re.findall(r'^\. "\$repo/(tests/ui-[^"]+\.sh)"$', driver, re.M)
assert "tests/ui-captures-sweep.sh" in sources
# Sample input: [[ ${#wanted[@]} -eq 0 ]] && wanted=(cursor scroll scrollbar touchpad terminal open rows click clickedge ctrlclick viewrestart dd ddclick collide sortrestart duallaunch dirsortstale editplace mute placemenu runscript unmounted sidebar menu background hidden selection watch optical select colour lifted icons thumbs hashcache stale nosweep oem header columnresize columnautofit overflow focus railpointer preview pdffocus network netmark networkauth networktimeout gvfs sharebrowser unmount phones trasharm eject poweroff rename renamefirst renamelife taildrop providers grid columns columnsbackground operations tabs tabdrag openterminal makeexec renderer settings makedefault scrolllane clickthrough wheelunder overlays views formats previewviews reclick colroot hangshare hanglisting hanginspect openwithdesign noblank previewswap transferlive recent middleclick opentab xwundo)
wanted = re.search(r'\]\] && wanted=\(([^)]*)\)', driver).group(1).split()
assert "capsweep" not in wanted and "capsweeplow" not in wanted
# Sample input: xwdrag_glide() {
definitions = set(re.findall(r'^(\w+)\(\)', driver, re.M))
for source in sources:
    # Sample input: sweep_shot() {
    definitions.update(re.findall(r'^(\w+)\(\)', (root / source).read_text(), re.M))
assert {"case_capsweep", "case_capsweeplow"} <= definitions
# Sample input: function themeLoaded(): bool { return Theme.ready }
readers = set(re.findall(r'function (\w+)\(', (root / "ui/Ipc.qml").read_text()))
# Sample input: sweep_wait previewOpen true
used = set(re.findall(r'\b(?:ipc|sweep_wait|sweep_text|menus_expect)\s+(\w+)', capture))
# Sample input: xwdrag_qs "$bid" listingDropActive
used.update(re.findall(r'\bxwdrag_qs "\$[ab]id" (\w+)', capture))
assert not used - readers, f"missing read-only IPC readers: {used - readers}"
lines = capture.splitlines()
for index, line in enumerate(lines):
    if line.startswith("case_cap"):
        assert lines[index - 1].startswith("# "), f"case lacks surface comment: {line}"
# Sample input: foreground = "#DFE8E0"
palette = tomllib.loads((root / "tests/fixtures/cool-dawn/colors.toml").read_text())
assert palette == {"accent": "#A9C6B7", "selection": "#46594F", "background": "#26302D", "foreground": "#DFE8E0", "muted": "#B0C3B7"}
ast.parse((root / "tests/ui-captures-sweep-picker.py").read_text())
print(f"CAPSWEEP_CHECK cases=2 sourced-libraries={len(sources)} IPC-readers={len(used)} palette=5 Python=parse-ok")
PY
. "$repo/tests/ui-captures-sweep.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
settle() { :; }
assert_theme() { [[ "$test_theme" == true ]] || fail 'theme unparsed'; }
token_of() { printf '%s\n' "$test_size"; }
ipc() { case "$1" in bodyPx) printf '%s\n' "$test_size" ;; path) printf '%s\n' "$test_path" ;; esac; }
shot() { [[ "$test_capture" == true ]] || fail 'capture refused'; printf 'PNG\n' > "$evidence_dir/$1.png"; }
magick() { printf '%s' "$test_dimensions"; }
evidence_dir="$scratch"
test_size=12 test_theme=true test_capture=true test_dimensions=1320x820
if ( sweep_shot text-size-refused ) > "$scratch/refused.log" 2>&1; then fail 'size 12 accepted'; fi
[[ ! -e "$scratch/sweep-text-size-refused.png" ]] || fail 'bad font produced a shot'
test_size=14 test_theme=false
if ( sweep_shot theme-refused ) > "$scratch/refused.log" 2>&1; then fail 'unparsed theme accepted'; fi
test_theme=true test_capture=false
if ( sweep_shot capture-refused ) > "$scratch/refused.log" 2>&1; then fail 'failed screenshot accepted'; fi
test_capture=true test_dimensions=invalid
if ( sweep_shot dimensions-refused ) > "$scratch/refused.log" 2>&1; then fail 'invalid dimensions accepted'; fi
[[ ! -e "$scratch/manifest.tsv" ]] || fail 'refused capture reached the manifest'
test_dimensions=1320x820
sweep_shot successful > "$scratch/success.log"
[[ "$(cat "$scratch/success.log")" == 'SWEEP sweep-successful 1320x820' ]] || fail 'per-shot line is wrong'
[[ "$(cat "$scratch/manifest.tsv")" == $'sweep-successful\t1320x820' ]] || fail 'manifest is wrong'
printf 'CAPSWEEP_CHECK refusal-controls=4 success=1\n'
# Run the real state composer with native side effects stubbed, to catch invalid default JSON.
fixture_root="$scratch"
sweep_root="$scratch/suite"
mkdir -p "$sweep_root/views"
printf 'fixture\n' > "$sweep_root/views/a.txt"
kill_flea() { :; }
launch() { [[ "$1" == "$sweep_root/views" ]] || fail 'unexpected launch path'; test_path="$1"; }
cap_resize() { [[ "$*" == '1320 820' ]] || fail 'unexpected viewport'; }
wait_listing() { [[ "$1" == 1 ]] || fail 'unexpected listing count'; }
seed_ui_state() { printf '%s\n' "$2" > "$scratch/seeded.json"; }
sweep_launch "$sweep_root/views"
jq -e '.view == "list" and .display.textSize.mode == 14 and .preview.thumbSize == "medium"' "$scratch/seeded.json" >/dev/null
sweep_launch "$sweep_root/views" '{"view":"grid","preview":{"thumbSize":"large"}}'
jq -e '.view == "grid" and .preview.thumbSize == "large" and .preview.column and .display.textSize.mode == 14' "$scratch/seeded.json" >/dev/null
printf 'CAPSWEEP_CHECK state-composition=2\n'
python3 -B "$repo/tests/capsweep-controls.py" "$scratch" "$repo"
python3 "$repo/tests/capsweep-ipc.py" "$scratch" "$repo"
