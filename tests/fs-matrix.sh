#!/usr/bin/env bash
# Headless backend matrix over ten filesystems plus a kernel NFSv4 round (ROOTCAUSE.md section 5,
# piece 1). Each filesystem is mkfs'd into an image under a marked scratch root, loop-mounted once
# through as_root, then driven with flea --backend requests and asserted on disk and on the wire.
# Sample listed line: {"t":"listed","n":9,"read":0.040,"sort":0.010,"v":42,"path":"/mnt/x"}
# Sample rows line: {"t":"rows","start":0,"rows":[{"n":"a.txt","d":false,"s":3,"m":929553600,"p":33188,"i":"text-x-generic","t":false,"k":0}],"kinds":["Plain text document"],"ms":1.250,"listing":1}
set -u
cd "$(dirname "$0")/.." || exit 1

BIN=${BIN:-./target/debug/flea}
DRY=0
SMOKE=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --smoke) SMOKE=1 ;;
    *) printf 'fs-matrix.sh: usage: fs-matrix.sh [--dry-run|--smoke]\n' >&2; exit 2 ;;
  esac
done

# A missing binary here would run every check below against nothing and report product failures.
if [ "$DRY" = 0 ] && [ ! -x "$BIN" ]; then
  printf 'fs-matrix.sh: no binary at %s, build it (cargo build) or set BIN\n' "$BIN" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { printf 'fs-matrix.sh: jq is required to read the wire\n' >&2; exit 1; }

# Root steps run through this one function, so the controller runs the script with sudo -n on a VPS.
as_root() {
  if [ "$DRY" = 1 ]; then printf 'would run as root:'; printf ' %s' "$@"; printf '\n'; return 0; fi
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi
}

# Fail closed when loop mounts are impossible: neither root nor a non-interactive sudo.
if [ "$DRY" = 0 ] && [ "$SMOKE" = 0 ]; then
  if [ "$(id -u)" != 0 ] && ! sudo -n true 2>/dev/null; then
    printf 'fs-matrix.sh: root is required for loop mounts, run with sudo -n\n' >&2
    exit 1
  fi
fi

# Ten filesystems, each named by its mkfs tool so a missing tool skips its row by name.
FSLIST="vfat exfat ntfs3 ntfs-3g ext4 btrfs xfs f2fs iso9660 udf"
# Every destructive path lives under this marked root, checked absolute and non-empty before delete.
ROOT=""
HARNESS=""
fail=0
pass=0
skip=0

track_loops() { printf '%s\n' "$1" >> "$ROOT/loops"; }
note_mnt() { printf '%s\n' "$1" >> "$ROOT/mnts"; }

cleanup() {
  if [ -n "$ROOT" ] && [ -f "$ROOT/mnts" ]; then
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      as_root umount -l "$m" 2>/dev/null || true
    done < "$ROOT/mnts"
  fi
  # Unexport what the NFS round exported, so no 127.0.0.1 export survives the run.
  if [ -n "$ROOT" ] && [ -f "$ROOT/exports" ]; then
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      as_root exportfs -u "$e" 2>/dev/null || true
    done < "$ROOT/exports"
  fi
  if [ -n "$ROOT" ] && [ -f "$ROOT/loops" ]; then
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      as_root losetup -d "$l" 2>/dev/null || true
    done < "$ROOT/loops"
  fi
  if [ -n "$ROOT" ]; then
    case "$ROOT" in /*/*) [ -f "$ROOT/.flea-test-sandbox" ] && rm -rf "$ROOT" ;; esac
  fi
}
trap cleanup EXIT HUP INT TERM

check() {
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok   %s\n' "$1";
  else fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}
skip_line() { skip=$((skip + 1)); printf 'SKIP %s\n' "$1"; }

# One backend per round, because the undo journal is process-lifetime by design.
start_backend() {
  rm -f "$HARNESS/out"; : > "$HARNESS/out"
  FRESH_FROM=0
  rm -f "$HARNESS/in"; mkfifo "$HARNESS/in"
  "$BIN" --backend < "$HARNESS/in" > "$HARNESS/out" 2> "$HARNESS/err" &
  BACKEND_PID=$!
  exec 3> "$HARNESS/in"
}
# A wedged backend never answers quit, so the wait is bounded and the tree is killed, never joined.
# No indefinite wait at the end either: a backend stuck in D state cannot be reaped at all, so the
# poll gives up and the exit trap leaves the corpse for init instead of hanging the controller.
stop_backend() {
  printf '%s\n' '{"c":"quit"}' >&3 || true
  exec 3>&- 2>/dev/null || true
  local i
  for i in $(seq 1 200); do kill -0 "$BACKEND_PID" 2>/dev/null || break; sleep 0.05; done
  kill -KILL "$BACKEND_PID" 2>/dev/null || true
  for i in $(seq 1 100); do kill -0 "$BACKEND_PID" 2>/dev/null || break; sleep 0.05; done
  kill -0 "$BACKEND_PID" 2>/dev/null || wait "$BACKEND_PID" 2>/dev/null || true
  BACKEND_PID=""
}
send() { printf '%s\n' "$1" >&3; }
# A bounded poll over the log file, never a background watcher, so a hung backend fails loudly.
# Every await reads only lines after the fresh marker, so an answer can never match a previous
# round's line of the same shape; each send below is preceded by fresh for exactly this reason.
await() {
  local pattern="$1" limit="${2:-200}" i
  for i in $(seq 1 "$limit"); do
    tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" 2>/dev/null | grep -q -- "$pattern" && return 0
    sleep 0.05
  done
  return 1
}
seen() { grep -c -- "$1" "$HARNESS/out" 2>/dev/null | tr -d ' ' || true; }
# Truncating the log mid-backend leaves NUL holes at the writer's stale offset, so freshness is a
# line marker instead: fresh records the count and seenf counts only lines after it.
fresh() { FRESH_FROM=$(wc -l < "$HARNESS/out"); }
seenf() { tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" 2>/dev/null | grep -c -- "$1" | tr -d ' ' || true; }
# Ten seconds of quiet, the same bound the trash browser already uses, so a wedged call is data.
have_dbus() { [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || command -v dbus-run-session >/dev/null 2>&1; }

# The seeded tree of battery check 3, scaled to a matrix round: hidden files, NFC and NFD names, a
# long name, a 1999 mtime, and a 60-file directory. Top level holds 6 files, 2 dirs, and the link.
NFC_NAME="caf$(printf '\303\251')-nfc.txt"
NFD_NAME="caf$(printf 'e\314\201')-nfd.txt"
LONG_BASENAME="$(python3 -c 'print("n"*246)').txt"
# Nine with the symlink, eight without: six files plus sub and many in both cases.
SEED_TOP_LINK=9
SEED_TOP_NOLINK=8
seed_tree() {
  local dir="$1" links="$2" i
  mkdir -p "$dir/sub" "$dir/many"
  printf 'seed' > "$dir/alpha.txt"
  printf 'seed' > "$dir/.hidden.txt"
  printf 'seed' > "$dir/$NFC_NAME"
  printf 'seed' > "$dir/$NFD_NAME"
  printf 'seed' > "$dir/$LONG_BASENAME"
  printf 'seed' > "$dir/old.txt"
  touch -d '1999-06-15 12:00:00 UTC' "$dir/old.txt"
  for i in $(seq -w 1 60); do printf 'x' > "$dir/many/f$i.txt"; done
  if [ "$links" = 1 ]; then ln -s alpha.txt "$dir/rel-link"; fi
}

# Per-filesystem shape: mkfs tool, image MiB, mkfs argv, mount fstype and the class the checks switch
# on (vfat-like, ntfs-like, native, or readonly). All sizes are MiB, named, not bare.
fs_config() {
  case "$1" in
    vfat) printf 'mkfs.vfat|5120|mkfs.vfat -F 32 -n FLEA-VFAT|vfat|vfatlike' ;;
    exfat) printf 'mkfs.exfat|2048|mkfs.exfat -L FLEA-EXFAT|exfat|vfatlike' ;;
    ntfs3) printf 'mkntfs|2048|mkntfs -F -L FLEA-NTFS|ntfs3|ntfslike' ;;
    ntfs-3g) printf 'mkntfs|2048|mkntfs -F -L FLEA-NTFS3G|ntfs-3g|ntfsfuselike' ;;
    ext4) printf 'mkfs.ext4|2048|mkfs.ext4 -q -L FLEA-EXT4|ext4|native' ;;
    btrfs) printf 'mkfs.btrfs|2048|mkfs.btrfs -q -L FLEA-BTRFS|btrfs|native' ;;
    xfs) printf 'mkfs.xfs|2048|mkfs.xfs -q -L FLEA-XFS|xfs|native' ;;
    f2fs) printf 'mkfs.f2fs|2048|mkfs.f2fs -f -l FLEA-F2FS|f2fs|native' ;;
    iso9660) printf 'xorrisofs|0|xorrisofs -J -R -V FLEA-ISO|iso9660|readonly' ;;
    udf) printf 'mkudffs|1024|mkudffs --media-type=hd -b 512 --utf8 -l FLEA-UDF|udf|native' ;;
  esac
}

# The ops.sh lesson: the fifo and the log stay on the host filesystem, never inside the payload dir,
# because vfat, exfat and iso9660 cannot hold a fifo at all. Every check below takes the mount dir.
c_list() {
  local mnt="$1" want="$2" out n
  fresh
  send "{\"c\":\"list\",\"path\":\"$mnt\",\"first\":70,\"hidden\":true}"
  await '"t":"listed"' || { check "$mnt list answers" "listed" "timeout"; return; }
  out=$(grep '"t":"listed"' "$HARNESS/out" | tail -1)
  n=$(printf '%s' "$out" | grep -oE '"n":[0-9]+' | cut -d: -f2)
  check "$mnt list count" "$want" "$n"
  fresh
  send '{"c":"window","start":0,"count":70}'
  await '"t":"rows"' || { check "$mnt rows answer" "rows" "timeout"; return; }
  out=$(grep '"t":"rows"' "$HARNESS/out" | tail -1)
  check "$mnt NFC name listed" "1" "$(printf '%s' "$out" | grep -c -F "$NFC_NAME")"
  check "$mnt NFD name listed" "1" "$(printf '%s' "$out" | grep -c -F "$NFD_NAME")"
  check "$mnt long name listed" "1" "$(printf '%s' "$out" | grep -c -F "$LONG_BASENAME")"
  check "$mnt hidden file listed" "1" "$(printf '%s' "$out" | grep -c -F '.hidden.txt')"
  # 1999 is epoch 929553600 and vfat keeps 2 s granularity, so the read-back only has to be old.
  check "$mnt 1999 mtime is old, not zeroed" "1" "$(printf '%s' "$out" | jq '[.rows[] | select(.n=="old.txt" and .m > 0 and .m < 946684800)] | length')"
  fresh
  send '{"c":"fsinfo"}'
  await '"t":"fsinfo"' || { check "$mnt fsinfo answers" "fsinfo" "timeout"; return; }
  out=$(grep '"t":"fsinfo"' "$HARNESS/out" | tail -1)
  check "$mnt fsinfo names the filesystem, not hex" "0" "$(printf '%s' "$out" | grep -c '"fs":"0x')"
}
c_mkdir() {
  local mnt="$1"
  fresh
  send "{\"c\":\"mkdir\",\"path\":\"$mnt\",\"name\":\"made-dir\"}"
  await '"t":"made"' || { check "$mnt mkdir answers" "made" "timeout"; return; }
  check "$mnt mkdir ok" "1" "$(seen '"t":"made","ok":true')"
  check "$mnt dir on disk" "yes" "$([ -d "$mnt/made-dir" ] && echo yes || echo no)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt mkdir undo answers" "undone" "timeout"; return; }
  check "$mnt mkdir undone" "no" "$([ -e "$mnt/made-dir" ] && echo yes || echo no)"
}
c_newfile() {
  local mnt="$1"
  fresh
  send "{\"c\":\"newfile\",\"path\":\"$mnt\",\"name\":\"made.txt\",\"id\":11}"
  await '"t":"menuaction"' || { check "$mnt newfile answers" "menuaction" "timeout"; return; }
  check "$mnt newfile ok" "1" "$(seen '"t":"menuaction","id":11,"op":"newFile","ok":true')"
  check "$mnt file on disk" "yes" "$([ -f "$mnt/made.txt" ] && echo yes || echo no)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt newfile undo answers" "undone" "timeout"; return; }
  check "$mnt newfile undone" "no" "$([ -e "$mnt/made.txt" ] && echo yes || echo no)"
}
c_rename() {
  local mnt="$1"
  printf 'body' > "$mnt/before.txt"
  fresh
  send "{\"c\":\"rename\",\"path\":\"$mnt/before.txt\",\"to\":\"after.txt\"}"
  await '"t":"renamed"' || { check "$mnt rename answers" "renamed" "timeout"; return; }
  check "$mnt rename ok" "1" "$(seen '"t":"renamed","ok":true')"
  check "$mnt new name on disk" "yes" "$([ -f "$mnt/after.txt" ] && echo yes || echo no)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt rename undo answers" "undone" "timeout"; return; }
  check "$mnt rename undone" "yes" "$([ -f "$mnt/before.txt" ] && echo yes || echo no)"
}
# Defect 11: case-only rename on vfat, exfat and hfsplus is EEXIST today, and plain rename(2) leaves
# the old spelling, so the fixed path goes through a temp sibling and lands on the new spelling.
c_caseonly() {
  local mnt="$1" class="$2"
  [ "$class" = "readonly" ] && { skip_line "$mnt case-only rename is read-only media"; return; }
  printf 'case' > "$mnt/case-a.txt"
  fresh
  send "{\"c\":\"rename\",\"path\":\"$mnt/case-a.txt\",\"to\":\"CASE-A.TXT\"}"
  if await '"t":"renamed"' 200; then :; elif await '"t":"error"' 20; then :;
  else check "$mnt case-only answers" "renamed or error" "timeout"; return; fi
  check "$mnt case-only lands on the new spelling" "yes" "$([ -f "$mnt/CASE-A.TXT" ] && echo yes || echo no)"
  check "$mnt case-only leaves no twin behind" "1" "$(ls "$mnt" | grep -c -i '^case-a\.txt$')"
  if tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" | grep -q '"t":"renamed","ok":true'; then
    fresh
    send '{"c":"undo"}'
    await '"t":"undone"' || { check "$mnt case-only undo answers" "undone" "timeout"; return; }
    check "$mnt case-only undone" "yes" "$([ -f "$mnt/case-a.txt" ] && echo yes || echo no)"
  fi
}
# Defect 14: vfat refuses : ? and a trailing space with EINVAL and silently strips a trailing dot.
c_illegal() {
  local mnt="$1" class="$2" name
  [ "$class" = "readonly" ] && { skip_line "$mnt illegal names are read-only media"; return; }
  case "$class" in vfatlike) ;; *) skip_line "$mnt illegal names only apply to FAT names"; return ;; esac
  printf 'seed' > "$mnt/legal.txt"
  for name in 'a:b' 'a?b' 'trail '; do
    fresh
    send "{\"c\":\"rename\",\"path\":\"$mnt/legal.txt\",\"to\":\"$name\"}"
    await '"where":"rename"' || { check "$mnt illegal [$name] refused" "error" "timeout"; continue; }
    check "$mnt illegal [$name] refused" "1" "$(seenf '"where":"rename"')"
    check "$mnt illegal [$name] creates nothing" "no" "$([ -e "$mnt/$name" ] && echo yes || echo no)"
  done
  fresh
  send "{\"c\":\"rename\",\"path\":\"$mnt/legal.txt\",\"to\":\"trail.\"}"
  if await '"t":"renamed"' 100; then :; elif await '"where":"rename"' 100; then :;
  else check "$mnt trailing dot answers" "an answer" "timeout"; return; fi
  check "$mnt trailing dot is refused, never silently stripped" "0" "$(seenf '"t":"renamed","ok":true')"
  check "$mnt no stripped twin left behind" "no" "$([ -e "$mnt/trail" ] && echo yes || echo no)"
}
c_copy_small() {
  local mnt="$1"
  printf 'small-bytes' > "$HARNESS/small.txt"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"copy\",\"paths\":[\"$HARNESS/small.txt\"],\"dest\":\"$mnt\"}"
  await '"t":"transferdone"' 400 || { check "$mnt copy answers" "transferdone" "timeout"; return; }
  check "$mnt copy done" "1" "$(seenf '"t":"transferdone","id":[0-9]*,"ok":1,"failed":0')"
  check "$mnt copy on disk" "small-bytes" "$(cat "$mnt/small.txt" 2>/dev/null)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt copy undo answers" "undone" "timeout"; return; }
  check "$mnt copy undone" "no" "$([ -e "$mnt/small.txt" ] && echo yes || echo no)"
}
# One GiB in and back out, proving throughput rather than just the handshake, then undone.
c_copy_big() {
  local mnt="$1" size
  [ -f "$HARNESS/big1g" ] || truncate -s 1G "$HARNESS/big1g"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"copy\",\"paths\":[\"$HARNESS/big1g\"],\"dest\":\"$mnt\"}"
  await '"t":"transferdone"' 1200 || { check "$mnt 1 GiB copy answers" "transferdone" "timeout"; return; }
  size=$(stat -c %s "$mnt/big1g" 2>/dev/null || printf '0')
  check "$mnt 1 GiB copy lands whole" "1073741824" "$size"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt 1 GiB undo answers" "undone" "timeout"; return; }
  check "$mnt 1 GiB undone" "no" "$([ -e "$mnt/big1g" ] && echo yes || echo no)"
}
# Defect 15: no 4 GiB or free-space check, so EFBIG after 4 GiB leaves a partial behind.
c_bigrefuse() {
  local mnt="$1" class="$2" size
  case "$class" in vfatlike) ;; *) skip_line "$mnt 4 GiB refusal is a FAT32 limit"; return ;; esac
  [ -f "$HARNESS/big45" ] || truncate -s 4608M "$HARNESS/big45"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"copy\",\"paths\":[\"$HARNESS/big45\"],\"dest\":\"$mnt\"}"
  await '"t":"transferdone"' 6000 || { check "$mnt oversize copy answers" "transferdone" "timeout"; return; }
  check "$mnt oversize copy fails, never lands" "1" "$(seenf '"t":"transferdone","id":[0-9]*,"ok":0,"failed":1')"
  size=$(stat -c %s "$mnt/big45" 2>/dev/null || printf '0')
  check "$mnt no 4 GiB partial left behind" "1" "$([ "$size" -lt 4294967296 ] && echo 1 || echo 0)"
  rm -f "$mnt/big45"
}
c_moves() {
  local mnt="$1" other="$2"
  printf 'same-dev' > "$mnt/mv-in.txt"
  mkdir -p "$mnt/mvdir"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"move\",\"paths\":[\"$mnt/mv-in.txt\"],\"dest\":\"$mnt/mvdir\"}"
  await '"t":"transferdone"' 400 || { check "$mnt same-device move answers" "transferdone" "timeout"; return; }
  check "$mnt same-device move lands" "same-dev" "$(cat "$mnt/mvdir/mv-in.txt" 2>/dev/null)"
  check "$mnt same-device source gone" "no" "$([ -e "$mnt/mv-in.txt" ] && echo yes || echo no)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt same-device undo answers" "undone" "timeout"; return; }
  check "$mnt same-device undone" "yes" "$([ -f "$mnt/mv-in.txt" ] && echo yes || echo no)"
  printf 'cross-dev' > "$other/x.txt"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"move\",\"paths\":[\"$other/x.txt\"],\"dest\":\"$mnt\"}"
  await '"t":"transferdone"' 400 || { check "$mnt cross-device move answers" "transferdone" "timeout"; return; }
  check "$mnt cross-device move lands" "cross-dev" "$(cat "$mnt/x.txt" 2>/dev/null)"
  check "$mnt cross-device source gone" "no" "$([ -e "$other/x.txt" ] && echo yes || echo no)"
  fresh
  send '{"c":"undo"}'
  await '"t":"undone"' || { check "$mnt cross-device undo answers" "undone" "timeout"; return; }
  check "$mnt cross-device undone" "yes" "$([ -f "$other/x.txt" ] && echo yes || echo no)"
}
# Defect 16: EPERM on vfat/exfat reads as access trouble; the fixed sentence names the capability.
# The link lands in its own directory, because the source name is already taken in this one.
c_links() {
  local mnt="$1" class="$2" want_ok
  [ "$class" = "readonly" ] && { skip_line "$mnt links are read-only media"; return; }
  case "$class" in vfatlike) want_ok="0" ;; *) want_ok="1" ;; esac
  mkdir -p "$mnt/linkdest"
  printf 'link-target' > "$mnt/lt.txt"
  fresh
  send "{\"c\":\"link\",\"op\":\"relative\",\"paths\":[\"$mnt/lt.txt\"],\"dest\":\"$mnt/linkdest\"}"
  await '"t":"linked"' || { check "$mnt symlink answers" "linked" "timeout"; return; }
  check "$mnt symlink ok count" "$want_ok" "$(tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" | grep '"t":"linked"' | tail -1 | grep -oE '"ok":[0-9]+' | cut -d: -f2)"
  if [ "$want_ok" = "1" ]; then
    check "$mnt symlink on disk" "yes" "$([ -L "$mnt/linkdest/lt.txt" ] && echo yes || echo no)"
    fresh
    send '{"c":"undo"}'
    await '"t":"undone"' || { check "$mnt symlink undo answers" "undone" "timeout"; return; }
    check "$mnt symlink undone" "no" "$([ -e "$mnt/linkdest/lt.txt" ] && echo yes || echo no)"
  else
    check "$mnt no symlink left behind" "0" "$(find "$mnt/linkdest" -mindepth 1 | wc -l | tr -d ' ')"
  fi
  fresh
  send "{\"c\":\"link\",\"op\":\"hard\",\"paths\":[\"$mnt/lt.txt\"],\"dest\":\"$mnt/linkdest\"}"
  await '"t":"linked"' || { check "$mnt hardlink answers" "linked" "timeout"; return; }
  check "$mnt hardlink ok count" "$want_ok" "$(tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" | grep '"t":"linked"' | tail -1 | grep -oE '"ok":[0-9]+' | cut -d: -f2)"
  if [ "$want_ok" = "1" ]; then
    fresh
    send '{"c":"undo"}'
    await '"t":"undone"' || { check "$mnt hardlink undo answers" "undone" "timeout"; return; }
    check "$mnt hardlink undone" "no" "$([ -e "$mnt/linkdest/lt.txt" ] && echo yes || echo no)"
  fi
}
# Defect 12: chmod on vfat, exfat and ntfs-3g returns 0 while the mode stays put, yet ok is reported.
# Either an applied mode that reads back or a refusal that changes nothing, never ok over no change.
c_perms() {
  local mnt="$1" class="$2" mode
  [ "$class" = "readonly" ] && { skip_line "$mnt permissions are read-only media"; return; }
  printf 'mode' > "$mnt/pm.txt"
  chmod 644 "$mnt/pm.txt"
  fresh
  send "{\"c\":\"permissionsBatch\",\"paths\":[\"$mnt/pm.txt\"],\"modes\":[\"600\"],\"id\":21}"
  await '"t":"permissions"' || { check "$mnt permissions answer" "permissions" "timeout"; return; }
  mode=$(stat -c %a "$mnt/pm.txt")
  if tail -n "+$((FRESH_FROM + 1))" "$HARNESS/out" | grep -q '"t":"permissions","id":21,"op":"applyMany","ok":true'; then
    check "$mnt applied mode reads back" "600" "$mode"
  else
    check "$mnt refused mode stays put" "644" "$mode"
  fi
}
# Trash goes through gio on a private bus and home, proving the volume's own .Trash-<uid> dir.
c_trash() {
  local mnt="$1" class="$2" uid trashdir
  [ "$class" = "readonly" ] && { skip_line "$mnt trash is absent on read-only media"; return; }
  have_dbus || { skip_line "$mnt trash needs a session bus (dbus-run-session)"; return; }
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    dbus-run-session -- gio trash --list >/dev/null 2>&1 || { skip_line "$mnt trash needs a working gio trash"; return; }
  fi
  uid=$(id -u)
  trashdir="$mnt/.Trash-$uid"
  printf 'trash me' > "$mnt/doomed.txt"
  export XDG_DATA_HOME="$HARNESS/xdg"
  mkdir -p "$XDG_DATA_HOME"
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    # No live bus, so trash and its undo run in one private session; the live backend would journal
    # neither, and its undo would reverse the wrong operation. Sample trash line: {"t":"trashed","ok":1,"failed":0}
    printf '%s\n' "{\"c\":\"trash\",\"paths\":[\"$mnt/doomed.txt\"]}" '{"c":"undo"}' '{"c":"quit"}' > "$HARNESS/one.req"
    dbus-run-session -- "$BIN" --backend < "$HARNESS/one.req" > "$HARNESS/one.out" 2>/dev/null
    cp "$HARNESS/one.out" "$HARNESS/out"
    check "$mnt trash ok" "1" "$(seen '"t":"trashed","ok":1,"failed":0')"
    check "$mnt file left the directory" "no" "$([ -e "$mnt/doomed.txt" ] && echo yes || echo no)"
    check "$mnt volume trash dir exists" "yes" "$([ -d "$trashdir" ] && echo yes || echo no)"
    check "$mnt trash undone" "trash me" "$(cat "$mnt/doomed.txt" 2>/dev/null)"
  else
    fresh
    send "{\"c\":\"trash\",\"paths\":[\"$mnt/doomed.txt\"]}"
    await '"t":"trashed"' 400 || { check "$mnt trash answers" "trashed" "timeout"; return; }
    check "$mnt trash ok" "1" "$(seen '"t":"trashed","ok":1,"failed":0')"
    check "$mnt file left the directory" "no" "$([ -e "$mnt/doomed.txt" ] && echo yes || echo no)"
    check "$mnt volume trash dir exists" "yes" "$([ -d "$trashdir" ] && echo yes || echo no)"
    fresh
    send '{"c":"undo"}'
    await '"t":"undone"' || { check "$mnt trash undo answers" "undone" "timeout"; return; }
    check "$mnt trash undone" "trash me" "$(cat "$mnt/doomed.txt" 2>/dev/null)"
  fi
}

round_fs() {
  local fs="$1" cfg tool size mkfs fstype class img loop mnt opts rest
  cfg=$(fs_config "$fs")
  tool=${cfg%%|*}; rest=${cfg#*|}; size=${rest%%|*}; rest=${rest#*|}
  mkfs=${rest%%|*}; rest=${rest#*|}; fstype=${rest%%|*}; class=${rest##*|}
  if [ "$DRY" = 1 ]; then
    printf 'would test %s: %s into image, loop-mount, seed, drive backend, unmount\n' "$fs" "$mkfs"
    return
  fi
  command -v "$tool" >/dev/null 2>&1 || { skip_line "$fs needs $tool, which is not on PATH"; return; }
  if [ "$fs" = "ntfs-3g" ]; then
    command -v ntfs-3g >/dev/null 2>&1 || { skip_line "ntfs-3g needs the ntfs-3g driver, which is not on PATH"; return; }
  fi
  img="$ROOT/img-$fs"
  mnt="$ROOT/mnt-$fs"
  mkdir -p "$mnt"
  if [ "$fs" = "iso9660" ]; then
    command -v xorrisofs >/dev/null 2>&1 || command -v genisoimage >/dev/null 2>&1 || { skip_line "$fs needs xorriso or genisoimage"; return; }
    seed_tree "$ROOT/seed-iso" 0
    if command -v xorrisofs >/dev/null 2>&1; then as_root xorrisofs -J -R -V FLEA-ISO -o "$img" "$ROOT/seed-iso" >/dev/null;
    else as_root genisoimage -J -R -V FLEA-ISO -o "$img" "$ROOT/seed-iso" >/dev/null; fi
    loop=$(as_root losetup --find --show "$img")
    track_loops "$loop"
    as_root mount -t iso9660 -o loop,ro "$loop" "$mnt"
  else
    truncate -s "${size}M" "$img"
    # Word-split here is the mkfs argv the table carries, one row per filesystem, never user input.
    # shellcheck disable=SC2086
    as_root $mkfs "$img" >/dev/null
    loop=$(as_root losetup --find --show "$img")
    track_loops "$loop"
    case "$fs" in
      vfat|exfat|ntfs3|udf) opts="uid=$(id -u),gid=$(id -g)" ;;
      ntfs-3g) opts="uid=$(id -u),gid=$(id -g)" ;;
      *) opts="" ;;
    esac
    if [ "$fs" = "ntfs-3g" ]; then as_root ntfs-3g "$loop" "$mnt" -o "$opts";
    elif [ -n "$opts" ]; then as_root mount -t "$fstype" -o "loop,$opts" "$loop" "$mnt";
    else as_root mount -t "$fstype" -o loop "$loop" "$mnt"; fi
    case "$fs" in ext4|btrfs|xfs|f2fs|udf) as_root chown -R "$(id -u):$(id -g)" "$mnt" ;; esac
    [ "$fs" = "btrfs" ] && btrfs subvolume create "$mnt/sub" >/dev/null 2>&1 || true
    if [ "$class" != "readonly" ]; then seed_tree "$mnt" 1; fi
  fi
  mountpoint -q "$mnt" || { skip_line "$fs mounted nothing at $mnt"; return; }
  note_mnt "$mnt"
  start_backend
  if [ "$fs" = "iso9660" ]; then c_list "$mnt" "$SEED_TOP_NOLINK"; else c_list "$mnt" "$SEED_TOP_LINK"; fi
  if [ "$class" != "readonly" ]; then
    c_mkdir "$mnt"
    c_newfile "$mnt"
    c_rename "$mnt"
    c_caseonly "$mnt" "$class"
    c_illegal "$mnt" "$class"
    c_copy_small "$mnt"
    c_copy_big "$mnt"
    c_bigrefuse "$mnt" "$class"
    c_moves "$mnt" "$HARNESS/xdev"
    c_links "$mnt" "$class"
    c_perms "$mnt" "$class"
    c_trash "$mnt" "$class"
  else
    printf 'seed' > "$HARNESS/ro-probe"
    fresh
    send "{\"c\":\"transfer\",\"op\":\"copy\",\"paths\":[\"$HARNESS/ro-probe\"],\"dest\":\"$mnt\"}"
    await '"where":"transfer"' 200 || await '"failed":[1-9]' 200 || true
    check "$mnt write refused up front" "0" "$([ -e "$mnt/ro-probe" ] && echo 1 || echo 0)"
  fi
  stop_backend
  printf 'ROUND %s class=%s done\n' "$fs" "$class"
}

# The NFS complaint (ROOTCAUSE.md 4.1): rename-class operations fail, and a dead server must never
# freeze the pane. Exported to 127.0.0.1 only, unexported and unmounted in the trap.
round_nfs() {
  if [ "$DRY" = 1 ]; then
    printf 'would test nfs: export root to 127.0.0.1, mount hard then soft,timeo=50, rename and move, stop server, deadline checks\n'
    return
  fi
  command -v exportfs >/dev/null 2>&1 || { skip_line "nfs needs exportfs (nfs-utils)"; return; }
  mkdir -p "$ROOT/nfsroot" "$ROOT/mnt-nfshard" "$ROOT/mnt-nfssoft" "$ROOT/nfslocal"
  seed_tree "$ROOT/nfsroot" 1
  as_root exportfs -o "rw,sync,no_subtree_check,insecure" "127.0.0.1:$ROOT/nfsroot" || { skip_line "nfs export failed"; return; }
  printf '%s\n' "127.0.0.1:$ROOT/nfsroot" >> "$ROOT/exports"
  as_root mount -t nfs -o "vers=4,hard" "127.0.0.1:$ROOT/nfsroot" "$ROOT/mnt-nfshard" || { skip_line "nfs hard mount failed"; return; }
  mountpoint -q "$ROOT/mnt-nfshard" || { skip_line "nfs hard mount landed nowhere"; return; }
  note_mnt "$ROOT/mnt-nfshard"
  start_backend
  fresh
  send "{\"c\":\"list\",\"path\":\"$ROOT/mnt-nfshard\",\"first\":70,\"hidden\":true}"
  await '"t":"listed"' || { check "nfs hard list answers" "listed" "timeout"; stop_backend; return; }
  check "nfs hard list count" "$SEED_TOP_LINK" "$(grep '"t":"listed"' "$HARNESS/out" | tail -1 | grep -oE '"n":[0-9]+' | cut -d: -f2)"
  printf 'nfs' > "$ROOT/mnt-nfshard/before.txt"
  fresh
  send "{\"c\":\"rename\",\"path\":\"$ROOT/mnt-nfshard/before.txt\",\"to\":\"after.txt\"}"
  if await '"t":"renamed"' 400; then :; elif await '"where":"rename"' 400; then :;
  else check "nfs hard rename answers" "an answer" "timeout"; stop_backend; return; fi
  check "nfs hard rename lands" "yes" "$([ -f "$ROOT/mnt-nfshard/after.txt" ] && echo yes || echo no)"
  fresh
  send "{\"c\":\"transfer\",\"op\":\"move\",\"paths\":[\"$ROOT/mnt-nfshard/after.txt\"],\"dest\":\"$ROOT/nfslocal\"}"
  await '"t":"transferdone"' 400 || true
  check "nfs hard move out lands" "1" "$(seenf 'transferdone')"
  stop_backend
  as_root umount "$ROOT/mnt-nfshard"
  as_root mount -t nfs -o "vers=4,soft,timeo=50" "127.0.0.1:$ROOT/nfsroot" "$ROOT/mnt-nfssoft" || { skip_line "nfs soft mount failed"; return; }
  mountpoint -q "$ROOT/mnt-nfssoft" || { skip_line "nfs soft mount landed nowhere"; return; }
  note_mnt "$ROOT/mnt-nfssoft"
  start_backend
  printf 'nfs' > "$ROOT/mnt-nfssoft/soft-before.txt"
  fresh
  send "{\"c\":\"rename\",\"path\":\"$ROOT/mnt-nfssoft/soft-before.txt\",\"to\":\"soft-after.txt\"}"
  if await '"t":"renamed"' 400; then :; elif await '"where":"rename"' 400; then :;
  else check "nfs soft rename answers" "an answer" "timeout"; stop_backend; return; fi
  check "nfs soft rename lands" "yes" "$([ -f "$ROOT/mnt-nfssoft/soft-after.txt" ] && echo yes || echo no)"
  # Dead server: unexport and stop the server, then a local request on the same backend must still
  # answer inside its deadline while the NFS one errors instead of hanging the loop.
  as_root exportfs -u "127.0.0.1:$ROOT/nfsroot" 2>/dev/null || true
  if command -v systemctl >/dev/null 2>&1; then as_root systemctl stop nfs-server 2>/dev/null || true; fi
  seed_tree "$ROOT/nfslocal" 0
  fresh
  send "{\"c\":\"list\",\"path\":\"$ROOT/mnt-nfssoft\",\"first\":5,\"hidden\":true}"
  fresh
  send "{\"c\":\"list\",\"path\":\"$ROOT/nfslocal\",\"first\":70,\"hidden\":true}"
  if await "\"path\":\"$ROOT/nfslocal\"" 500; then
    check "nfs dead server keeps the local listing live" "1" "1"
  else
    check "nfs dead server keeps the local listing live" "an answer" "timeout"
  fi
  if await '"t":"error"' 500; then
    check "nfs dead server answers, never hangs" "1" "1"
  else
    check "nfs dead server answers, never hangs" "an error, not a hang" "timeout"
  fi
  stop_backend
}

if [ "$DRY" = 1 ]; then
  printf 'fs-matrix plan: %s then nfs\n' "$FSLIST"
  for fs in $FSLIST; do round_fs "$fs"; done
  round_nfs
  printf 'fs-matrix --dry-run ok\n'
  exit 0
fi

if [ "$SMOKE" = 1 ]; then
  ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flea-fs-smoke.XXXXXX") || exit 1
  case "$ROOT" in /*/*) ;; *) printf 'fs-matrix.sh: refusing unsafe scratch %s\n' "$ROOT" >&2; exit 1 ;; esac
  [ -n "$ROOT" ] || exit 1
  : > "$ROOT/.flea-test-sandbox"
  HARNESS="$ROOT/harness"
  mkdir -p "$HARNESS" "$HARNESS/xdev"
  mnt="$ROOT/native"
  mkdir -p "$mnt"
  seed_tree "$mnt" 1
  start_backend
  c_list "$mnt" "$SEED_TOP_LINK"
  c_mkdir "$mnt"
  c_newfile "$mnt"
  c_rename "$mnt"
  c_caseonly "$mnt" native
  c_copy_small "$mnt"
  c_moves "$mnt" "$HARNESS/xdev"
  c_links "$mnt" native
  c_perms "$mnt" native
  stop_backend
  printf 'fs-matrix --smoke: %s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
  [ "$fail" = 0 ]
  exit $?
fi

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flea-fs-matrix.XXXXXX") || exit 1
case "$ROOT" in /*/*) ;; *) printf 'fs-matrix.sh: refusing unsafe scratch %s\n' "$ROOT" >&2; exit 1 ;; esac
[ -n "$ROOT" ] || exit 1
: > "$ROOT/.flea-test-sandbox"
HARNESS="$ROOT/harness"
mkdir -p "$HARNESS" "$HARNESS/xdev" "$HARNESS/xdg"
for fs in $FSLIST; do round_fs "$fs"; done
round_nfs
printf 'fs-matrix: %s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" = 0 ]
