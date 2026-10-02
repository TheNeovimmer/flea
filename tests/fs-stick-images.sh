#!/usr/bin/env bash
# Builds the six native stick layouts of ROOTCAUSE.md section 5 as raw disk images (piece 2). Each
# image is small (under 1 GiB), labelled FLEA-<FS>, and seeded with the tree of battery check 3.
# Prints one JSON object per layout on stdout: {"layout":"vfat","image":"<path>",
# "expected_rows_off":[...],"expected_rows_on":[...],"note":"..."}. Sample expected row: "FLEA-VFAT".
set -u
cd "$(dirname "$0")/.." || exit 1

DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    *) printf 'fs-stick-images.sh: usage: fs-stick-images.sh [--dry-run]\n' >&2; exit 2 ;;
  esac
done
command -v jq >/dev/null 2>&1 || { printf 'fs-stick-images.sh: jq is required for the JSON output\n' >&2; exit 1; }

# Root steps run through this one function, so the controller runs the script with sudo -n on a VPS.
as_root() {
  if [ "$DRY" = 1 ]; then printf 'would run as root:'; printf ' %s' "$@"; printf '\n'; return 0; fi
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi
}

if [ "$DRY" = 0 ]; then
  if [ "$(id -u)" != 0 ] && ! sudo -n true 2>/dev/null; then
    printf 'fs-stick-images.sh: root is required for partitioning, run with sudo -n\n' >&2
    exit 1
  fi
fi

LAYOUTS="vfat exfat ntfs3 espdata espmsrswap isohybrid"
ROOT=""
fails=0
cleanup() {
  if [ -n "$ROOT" ] && [ -f "$ROOT/mnts" ]; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      as_root umount -l "$m" 2>/dev/null || true
    done < "$ROOT/mnts"
  fi
  if [ -n "$ROOT" ] && [ -f "$ROOT/loops" ]; then
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      as_root losetup -d "$l" 2>/dev/null || true
    done < "$ROOT/loops"
  fi
  # The images stay: writing them to the stick is the controller's step, so only mounts detach here.
}
trap cleanup EXIT HUP INT TERM
note_mnt() { printf '%s\n' "$1" >> "$ROOT/mnts"; }
track_loops() { printf '%s\n' "$1" >> "$ROOT/loops"; }
skip_line() { printf 'SKIP %s\n' "$1"; }
emit() { printf '{"layout":"%s","image":"%s","expected_rows_off":[%s],"expected_rows_on":[%s],"note":"%s"}\n' "$1" "$2" "$3" "$4" "$5"; }
qlist() { local s=""; local x; for x in "$@"; do s="$s\"$x\","; done; printf '%s' "${s%,}"; }

# Battery check 3 counts, named: files, dirs, the one big directory, and image sizes in MiB, named.
STICK_FILES=1000
STICK_DIRS=50
STICK_MANY=10000
MBR_ESP_START=64
MBR_ESP_SIZE=2048
# One seed tree on the host, copied per image, because building 11k files six times is the slow part.
# A symlink where supported: the vfat and exfat copies drop the link, which those drives cannot hold.
NFC_NAME="caf$(printf '\303\251')-nfc.txt"
NFD_NAME="caf$(printf 'e\314\201')-nfd.txt"
LONG_BASENAME="$(python3 -c 'print("n"*246)').txt"
seed_host() {
  local dir="$1" i d
  mkdir -p "$dir/seed/tree"
  for i in $(seq -w 1 "$STICK_FILES"); do printf 'seed' > "$dir/seed/tree/f$i.txt"; done
  for d in $(seq -w 1 "$STICK_DIRS"); do mkdir -p "$dir/seed/tree/d$d"; printf 'seed' > "$dir/seed/tree/d$d/in.txt"; done
  mkdir -p "$dir/seed/tree/many"
  for i in $(seq -w 1 "$STICK_MANY"); do printf 'x' > "$dir/seed/tree/many/g$i.txt"; done
  printf 'seed' > "$dir/seed/tree/.hidden.txt"
  printf 'seed' > "$dir/seed/tree/$NFC_NAME"
  printf 'seed' > "$dir/seed/tree/$NFD_NAME"
  printf 'seed' > "$dir/seed/tree/$LONG_BASENAME"
  printf 'seed' > "$dir/seed/tree/old.txt"
  touch -d '1999-06-15 12:00:00 UTC' "$dir/seed/tree/old.txt"
  ln -s f0001.txt "$dir/seed/tree/rel-link"
  # A real 64 px PNG from the stdlib alone, so the native thumbnail leg needs no fixture or tool.
  python3 - "$dir/seed/tree/thumb.png" <<'PY'
import struct, sys, zlib
w = h = 64
rows = []
for y in range(h):
    row = b"\x00"
    for x in range(w):
        row += bytes([(x * 4) % 256, (y * 4) % 256, 128])
    rows.append(row)
raw = b"".join(rows)
def chunk(kind, data):
    c = struct.pack(">I", len(data)) + kind + data
    return c + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
}
seed_copy() {
  local src="$1" dst="$2" nolinks="$3"
  cp -a "$src/seed/tree/." "$dst/"
  if [ "$nolinks" = 1 ]; then rm -f "$dst/rel-link"; fi
}
mounted_ok() {
  mountpoint -q "$1" || { printf 'fs-stick-images.sh: nothing mounted at %s\n' "$1" >&2; return 1; }
}

layout_vfat() {
  local img="$ROOT/stick-vfat.img" mb=256
  if [ "$DRY" = 1 ]; then
    printf 'would build vfat: %s MiB MBR 0x0c FAT32 label FLEA-VFAT, seeded\n' "$mb"
    emit vfat "$img" "$(qlist FLEA-VFAT)" "$(qlist FLEA-VFAT)" "baseline"
    return
  fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "vfat needs sfdisk"; return; }
  command -v mkfs.vfat >/dev/null 2>&1 || { skip_line "vfat needs mkfs.vfat"; return; }
  truncate -s "${mb}M" "$img"
  printf 'label: dos\n, type=0c\n' | as_root sfdisk -q "$img" >/dev/null
  local loop
  loop=$(as_root losetup --find --show -P "$img")
  track_loops "$loop"
  as_root mkfs.vfat -F 32 -n FLEA-VFAT "${loop}p1" >/dev/null
  mkdir -p "$ROOT/mnt-vfat"
  as_root mount -o "uid=$(id -u),gid=$(id -g)" "${loop}p1" "$ROOT/mnt-vfat"
  mounted_ok "$ROOT/mnt-vfat" || return 1
  note_mnt "$ROOT/mnt-vfat"
  seed_copy "$ROOT" "$ROOT/mnt-vfat" 1
  as_root umount "$ROOT/mnt-vfat"
  emit vfat "$img" "$(qlist FLEA-VFAT)" "$(qlist FLEA-VFAT)" "baseline"
}

layout_exfat() {
  local img="$ROOT/stick-exfat.img" mb=256
  if [ "$DRY" = 1 ]; then
    printf 'would build exfat: %s MiB MBR 0x07 label FLEA-EXFAT, seeded\n' "$mb"
    emit exfat "$img" "$(qlist FLEA-EXFAT)" "$(qlist FLEA-EXFAT)" "baseline"
    return
  fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "exfat needs sfdisk"; return; }
  command -v mkfs.exfat >/dev/null 2>&1 || { skip_line "exfat needs mkfs.exfat"; return; }
  truncate -s "${mb}M" "$img"
  printf 'label: dos\n, type=07\n' | as_root sfdisk -q "$img" >/dev/null
  local loop
  loop=$(as_root losetup --find --show -P "$img")
  track_loops "$loop"
  as_root mkfs.exfat -L FLEA-EXFAT "${loop}p1" >/dev/null
  mkdir -p "$ROOT/mnt-exfat"
  as_root mount -o "uid=$(id -u),gid=$(id -g)" "${loop}p1" "$ROOT/mnt-exfat"
  mounted_ok "$ROOT/mnt-exfat" || return 1
  note_mnt "$ROOT/mnt-exfat"
  seed_copy "$ROOT" "$ROOT/mnt-exfat" 1
  as_root umount "$ROOT/mnt-exfat"
  emit exfat "$img" "$(qlist FLEA-EXFAT)" "$(qlist FLEA-EXFAT)" "baseline"
}

# The #232 internal half: only the data row may appear, System Reserved hidden by label rule H4 and
# WinRE 0x27 hidden by type rule H3. Partition sizes are MiB, named, total under 1 GiB.
layout_ntfs3() {
  local img="$ROOT/stick-ntfs3.img" mb=700 sys_mb=50 data_mb=400 winre_mb=100
  if [ "$DRY" = 1 ]; then
    printf 'would build ntfs3: %s MiB MBR 0x07 %s MiB System Reserved plus data FLEA-NTFS plus 0x27 WinRE, seeded\n' "$mb" "$sys_mb"
    emit ntfs3 "$img" "$(qlist FLEA-NTFS)" "$(qlist FLEA-NTFS)" "System Reserved and WinRE hidden"
    return
  fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "ntfs3 needs sfdisk"; return; }
  command -v mkntfs >/dev/null 2>&1 || { skip_line "ntfs3 needs mkntfs"; return; }
  truncate -s "${mb}M" "$img"
  printf 'label: dos\n, size=%sM, type=07\n, size=%sM, type=07\n, size=%sM, type=27\n' "$sys_mb" "$data_mb" "$winre_mb" | as_root sfdisk -q "$img" >/dev/null
  local loop
  loop=$(as_root losetup --find --show -P "$img")
  track_loops "$loop"
  as_root mkntfs -F -L "System Reserved" "${loop}p1" >/dev/null 2>&1
  as_root mkntfs -F -L "FLEA-NTFS" "${loop}p2" >/dev/null 2>&1
  as_root mkntfs -F "${loop}p3" >/dev/null 2>&1
  mkdir -p "$ROOT/mnt-ntfs3"
  as_root mount -t ntfs3 -o "uid=$(id -u),gid=$(id -g)" "${loop}p2" "$ROOT/mnt-ntfs3"
  mounted_ok "$ROOT/mnt-ntfs3" || return 1
  note_mnt "$ROOT/mnt-ntfs3"
  as_root chown -R "$(id -u):$(id -g)" "$ROOT/mnt-ntfs3"
  seed_copy "$ROOT" "$ROOT/mnt-ntfs3" 0
  as_root umount "$ROOT/mnt-ntfs3"
  emit ntfs3 "$img" "$(qlist FLEA-NTFS)" "$(qlist FLEA-NTFS)" "System Reserved and WinRE hidden"
}

# GPT ESP plus a data partition: hfsplus when its mkfs exists, else ext4 labelled to say so, because
# hfsprogs is AUR-only on Arch. The ESP hides under rule H3 in both variants. Sizes are MiB, named.
layout_espdata() {
  local img="$ROOT/stick-espdata.img" mb=512 esp_mb=64 data_mb=400 label="FLEA-HFS" note="hfsplus data"
  if ! command -v mkfs.hfsplus >/dev/null 2>&1; then label="FLEA-NOHFSPLUS"; note="ext4 standing in for hfsplus"; fi
  if [ "$DRY" = 1 ]; then
    printf 'would build espdata: %s MiB GPT ESP %s MiB plus data %s, seeded\n' "$mb" "$esp_mb" "$label"
    emit espdata "$img" "$(qlist "$label")" "$(qlist "$label")" "$note"
    return
  fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "espdata needs sfdisk"; return; }
  command -v mkfs.vfat >/dev/null 2>&1 || { skip_line "espdata needs mkfs.vfat for the ESP"; return; }
  if command -v mkfs.hfsplus >/dev/null 2>&1; then :;
  elif command -v mkfs.ext4 >/dev/null 2>&1; then :;
  else skip_line "espdata needs mkfs.hfsplus or mkfs.ext4"; return; fi
  truncate -s "${mb}M" "$img"
  printf 'label: gpt\n, size=%sM, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n, size=%sM, type=48465300-0000-11AA-AA11-00306543ECAC\n' \
    "$esp_mb" "$data_mb" | as_root sfdisk -q "$img" >/dev/null
  local loop
  loop=$(as_root losetup --find --show -P "$img")
  track_loops "$loop"
  as_root mkfs.vfat -F 32 -n EFI "${loop}p1" >/dev/null
  if command -v mkfs.hfsplus >/dev/null 2>&1; then as_root mkfs.hfsplus -v "$label" "${loop}p2" >/dev/null 2>&1;
  else as_root mkfs.ext4 -q -L "$label" "${loop}p2" >/dev/null; fi
  mkdir -p "$ROOT/mnt-espdata"
  as_root mount "${loop}p2" "$ROOT/mnt-espdata"
  mounted_ok "$ROOT/mnt-espdata" || return 1
  note_mnt "$ROOT/mnt-espdata"
  as_root chown -R "$(id -u):$(id -g)" "$ROOT/mnt-espdata" 2>/dev/null || true
  seed_copy "$ROOT" "$ROOT/mnt-espdata" 0
  as_root umount "$ROOT/mnt-espdata"
  emit espdata "$img" "$(qlist "$label")" "$(qlist "$label")" "$note"
}

# GPT ext4 with ESP, MSR and swap: ESP, MSR and swap all hide, leaving only the data row. Sizes MiB.
layout_espmsrswap() {
  local img="$ROOT/stick-espmsrswap.img" mb=640 esp_mb=64 msr_mb=16 swap_mb=64 data_mb=400
  if [ "$DRY" = 1 ]; then
    printf 'would build espmsrswap: %s MiB GPT ESP plus MSR plus swap plus ext4 FLEA-EXT4, seeded\n' "$mb"
    emit espmsrswap "$img" "$(qlist FLEA-EXT4)" "$(qlist FLEA-EXT4)" "ESP MSR swap hidden"
    return
  fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "espmsrswap needs sfdisk"; return; }
  command -v mkfs.vfat >/dev/null 2>&1 || { skip_line "espmsrswap needs mkfs.vfat for the ESP"; return; }
  command -v mkfs.ext4 >/dev/null 2>&1 || { skip_line "espmsrswap needs mkfs.ext4"; return; }
  command -v mkswap >/dev/null 2>&1 || { skip_line "espmsrswap needs mkswap"; return; }
  truncate -s "${mb}M" "$img"
  printf 'label: gpt\n, size=%sM, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n, size=%sM, type=E3C9E316-0B5C-4DB8-817D-F92DF00215AE\n, size=%sM, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4\n, size=%sM, type=0FC63DAF-8483-4772-8E79-3D69D8477DE\n' \
    "$esp_mb" "$msr_mb" "$swap_mb" "$data_mb" | as_root sfdisk -q "$img" >/dev/null
  local loop
  loop=$(as_root losetup --find --show -P "$img")
  track_loops "$loop"
  as_root mkfs.vfat -F 32 -n EFI "${loop}p1" >/dev/null
  as_root mkswap "${loop}p3" >/dev/null
  as_root mkfs.ext4 -q -L FLEA-EXT4 "${loop}p4" >/dev/null
  mkdir -p "$ROOT/mnt-espmsrswap"
  as_root mount "${loop}p4" "$ROOT/mnt-espmsrswap"
  mounted_ok "$ROOT/mnt-espmsrswap" || return 1
  note_mnt "$ROOT/mnt-espmsrswap"
  as_root chown -R "$(id -u):$(id -g)" "$ROOT/mnt-espmsrswap"
  seed_copy "$ROOT" "$ROOT/mnt-espmsrswap" 0
  as_root umount "$ROOT/mnt-espmsrswap"
  emit espmsrswap "$img" "$(qlist FLEA-EXT4)" "$(qlist FLEA-EXT4)" "ESP MSR swap hidden"
}

# An isohybrid image written raw: partition 1 is 0x0 iso9660 and stays a row under the isohybrid undo
# of rule H3, its 0xef ESP hides. The table is stamped onto the ISO's own system area, which lives
# before sector 16 and never overlaps a volume descriptor, so lsblk sees partitions on a live ISO.
layout_isohybrid() {
  local img="$ROOT/stick-isohybrid.img"
  if [ "$DRY" = 1 ]; then
    printf 'would build isohybrid: ISO9660 FLEA-ISO with MBR 0x0 plus 0xef ESP, seeded\n'
    emit isohybrid "$img" "$(qlist FLEA-ISO)" "$(qlist FLEA-ISO)" "ISO row kept, ESP hidden"
    return
  fi
  if command -v xorrisofs >/dev/null 2>&1; then iso_tool="xorrisofs -J -R -V";
  elif command -v genisoimage >/dev/null 2>&1; then iso_tool="genisoimage -J -R -V";
  else skip_line "isohybrid needs xorriso or genisoimage"; return; fi
  command -v sfdisk >/dev/null 2>&1 || { skip_line "isohybrid needs sfdisk"; return; }
  # Word-split here is the ISO tool argv the branch above chose, never user input.
  # shellcheck disable=SC2086
  as_root $iso_tool FLEA-ISO -o "$img" "$ROOT/seed/tree" >/dev/null
  printf 'label: dos\n, type=00\n, start=%s, size=%s, type=ef\n' "$MBR_ESP_START" "$MBR_ESP_SIZE" | as_root sfdisk -q "$img" >/dev/null
  emit isohybrid "$img" "$(qlist FLEA-ISO)" "$(qlist FLEA-ISO)" "ISO row kept, ESP hidden"
}

if [ "$DRY" = 1 ]; then
  printf 'fs-stick-images plan: %s\n' "$LAYOUTS"
  ROOT="$PWD/.superpowers/tmp/flea-stick-plan"
  for layout in $LAYOUTS; do "layout_$layout"; done
  printf 'fs-stick-images --dry-run ok\n'
  exit 0
fi

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flea-stick-images.XXXXXX") || exit 1
case "$ROOT" in /*/*) ;; *) printf 'fs-stick-images.sh: refusing unsafe scratch %s\n' "$ROOT" >&2; exit 1 ;; esac
[ -n "$ROOT" ] || exit 1
: > "$ROOT/.flea-test-sandbox"
seed_host "$ROOT"
for layout in $LAYOUTS; do "layout_$layout" || fails=$((fails + 1)); done
printf 'images under %s\n' "$ROOT" >&2
[ "$fails" = 0 ]
