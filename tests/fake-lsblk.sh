#!/bin/bash
# Fake lsblk --bytes --json for the DEVICES rail battery and the native suite.
# Sample input: tests/fake-lsblk.sh esp-stick; one name, one JSON body on stdout.
set -u
name="${1:-all}"
sys='{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"parttype":null,"pttype":"gpt","partn":null,"uuid":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem","parttype":null,"pttype":"gpt","partn":1,"uuid":"11111111-1111-1111-1111-111111111111"}]}'
stick_disk='{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":124656812032,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null,"parttype":null,"pttype":"dos","partn":null,"uuid":null'
leaf() { printf '%s' "$1"; }
esp='{"name":"sda1","path":"/dev/sda1","label":"BOOT","mountpoints":[null],"rm":true,"tran":null,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System","parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","pttype":"gpt","partn":1,"uuid":"A1B2-C3D4"}'
sysres='{"name":"sda1","path":"/dev/sda1","label":"System Reserved","mountpoints":[null],"rm":false,"tran":null,"size":52428800,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x7","pttype":"dos","partn":1,"uuid":"2222222222222222"}'
winre='{"name":"sda2","path":"/dev/sda2","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":524288000,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x27","pttype":"dos","partn":2,"uuid":"3333333333333333"}'
msr='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":16777216,"type":"part","model":null,"fstype":null,"parttypename":null,"parttype":"e3c9e316-0b5c-4db8-817d-f92df00215ae","pttype":"gpt","partn":1,"uuid":null}'
lvm_pv='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"LVM2_member","parttypename":null,"parttype":"0x8e","pttype":"dos","partn":1,"uuid":"44444444-4444-4444-4444-444444444444"}'
raid='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"linux_raid_member","parttypename":null,"parttype":"0xfd","pttype":"dos","partn":1,"uuid":"55555555-5555-5555-5555-555555555555"}'
swap='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":["[SWAP]"],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap","parttype":"0x82","pttype":"dos","partn":1,"uuid":"66666666-6666-6666-6666-666666666666"}'
nofs='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":null,"parttype":null,"pttype":"dos","partn":1,"uuid":null}'
luks='{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":8589934592,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem","parttype":"0x83","pttype":"dos","partn":1,"uuid":"77777777-7777-7777-7777-777777777777"}'
iso='{"name":"sda1","path":"/dev/sda1","label":"FLEA-ISO","mountpoints":[null],"rm":true,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"iso9660","parttypename":null,"parttype":"0x0","pttype":"dos","partn":1,"uuid":"88888888-8888-8888-8888-888888888888"}'
stick() { printf '%s,"children":[%s]}' "$stick_disk" "$1"; }
case "$name" in
  esp-stick) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$esp")" ;;
  system-reserved) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$sysres")" ;;
  winre-027) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$winre")" ;;
  msr) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$msr")" ;;
  lvm-pv) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$lvm_pv")" ;;
  raid-member) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$raid")" ;;
  swap-stick) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$swap")" ;;
  nofs) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$nofs")" ;;
  luks) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$luks")" ;;
  isohybrid) printf '{"blockdevices":[%s,%s]}' "$sys" "$(stick "$iso")" ;;
  all) printf '{"blockdevices":[%s]}' "$sys" ;;
  *) echo "fake-lsblk.sh: unknown fixture $name" >&2; exit 2 ;;
esac
