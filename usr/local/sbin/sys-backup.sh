#!/usr/bin/env bash
is_recursive=
mount_only=
cleanup_only=
add_only=
disk_uuid=''

usage() {
  printf >&2 'usage: sys-backup.sh [mount|backup] DISK_UUID\n'
  exit 1
}

cleanup() {
  umount /backup
  cryptsetup close luks-backup-"$disk_uuid"
  udisksctl power-off -b /dev/disk/by-uuid/"$disk_uuid"
}

case "$1" in
  m|mount) mount_only=1 ;;
  u|unmount) cleanup_only=1 ;;
  a|add) add_only=1 ;;
  b|backup) ;;
  *) usage ;;
esac
disk_uuid="$2"

if [[ "${#disk_uuid}" -ne 36 ]]; then
  printf >&2 'Error: ( %s ) does not look like a UUID\n' "$disk_uuid"
  usage
elif [[ "$add_only" = 1 ]]; then
  printf 'Creating /etc/sys-backup/%s\n' "$disk_uuid"
  mkdir -m 755 -p /etc/sys-backup
  echo 'SYS_BACKUP_ENABLED=1' > /etc/sys-backup/"$disk_uuid"
  exit
fi

trap 'cleanup' EXIT
[[ "$cleanup_only" = 1 ]] && exit

if ! cryptsetup open \
    --key-file /root/cryptkeys/usb-"$disk_uuid".key \
    /dev/disk/by-uuid/"$disk_uuid" \
    luks-backup-"$disk_uuid"
then
  # attempt to recover from an already open device
  [[ "$is_recursive" = 'recursive' ]] && exit 1
  umount /backup
  cryptsetup close luks-backup-"$disk_uuid"
  exec env is_recursive='recursive' "${BASH_SOURCE[0]}" "$@" || exit
fi

mount -o compress-force=zstd /dev/mapper/luks-backup-"$disk_uuid" /backup || exit
[[ "$mount_only" = 1 ]] && exit 0

btrbk --config "/etc/btrbk/$disk_uuid.conf" --verbose run || exit

if [[ ! -e /backup/.btrfs-scrub-marker ]] \
   || ! find /backup -maxdepth 1 -mtime +29 -name '.btrfs-scrub-marker' -exec false {} +
then
  btrfs scrub start -B /backup || exit
  touch /backup/.btrfs-scrub-marker
fi
