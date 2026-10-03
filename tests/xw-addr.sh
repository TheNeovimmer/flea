#!/bin/bash
# Headless pin for xw_window_addr_now: the driver payload carries no pid, so the helper reads hyprctl.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" || exit 1
# Sample input: hyprctl clients -j answers a top-level array carrying pid and address.
cat > "$tmp/bin/hyprctl" <<'STUB'
#!/bin/sh
if [ "$#" -ne 2 ] || [ "$1" != clients ] || [ "$2" != -j ]; then
    printf 'xw-addr: unexpected hyprctl arguments: %s\n' "$*" >&2
    exit 2
fi
cat "$HYPRCTL_FIXTURE"
STUB
chmod +x "$tmp/bin/hyprctl" || exit 1
eval "$(sed -n '/^xw_window_addr_now()/,/^}/p' tests/ui.sh)" || exit 1
cat > "$tmp/two.json" <<'JSON'
[{"address":"0xaaa","pid":111,"title":"Flea"},{"address":"0xbbb","pid":222,"title":"Flea"}]
JSON
addr=$(HYPRCTL_FIXTURE="$tmp/two.json" PATH="$tmp/bin:$PATH" xw_window_addr_now 111) || exit 1
if [ "$addr" != "0xaaa" ]
then
echo "xw-addr: pid 111 gave $addr, not 0xaaa"
exit 1
fi
addr=$(HYPRCTL_FIXTURE="$tmp/two.json" PATH="$tmp/bin:$PATH" xw_window_addr_now 999) || exit 1
if [ -n "$addr" ]
then
echo "xw-addr: absent pid gave $addr, not empty"
exit 1
fi
cat > "$tmp/dup.json" <<'JSON'
[{"address":"0xaaa","pid":111,"title":"Flea"},{"address":"0xccc","pid":111,"title":"Flea"}]
JSON
addr=$(HYPRCTL_FIXTURE="$tmp/dup.json" PATH="$tmp/bin:$PATH" xw_window_addr_now 111) || exit 1
case "$addr" in
*'
'*)
echo "xw-addr: duplicate pid stays ambiguous, as the caller requires"
;;
*)
echo "xw-addr: duplicate pid gave one line, not two"
exit 1
;;
esac
echo "xw-addr: hyprctl pid lookup pins one, none and two matches"
