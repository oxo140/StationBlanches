#!/bin/bash
set -Eeuo pipefail
device=${1:?Nom du périphérique manquant}
[[ "$device" =~ ^[a-zA-Z0-9]+$ ]] || { echo "Nom de périphérique invalide" >&2; exit 1; }
[[ -b "/dev/$device" ]] || { echo "Périphérique bloc absent" >&2; exit 1; }
properties=$(udevadm info --query=property --name="/dev/$device")
grep -qx 'ID_BUS=usb' <<< "$properties" || { echo "Périphérique non USB refusé" >&2; exit 1; }
grep -qx 'ID_FS_USAGE=filesystem' <<< "$properties" || exit 1
target="/srv/station-blanche/media/$device"
install -d -m 0755 "$target"
if mountpoint -q "$target"; then
    echo "Point déjà monté, aucune modification : $target"
    exit 0
fi
filesystem=$(blkid -o value -s TYPE "/dev/$device")
case "$filesystem" in
    vfat|exfat) mount -t "$filesystem" -o ro,nosuid,nodev,noexec,umask=022 -- "/dev/$device" "$target" ;;
    ntfs) mount -t ntfs3 -o ro,nosuid,nodev,noexec,umask=022 -- "/dev/$device" "$target" ;;
    ext2) mount -t ext2 -o ro,nosuid,nodev,noexec -- "/dev/$device" "$target" ;;
    ext3|ext4) mount -t "$filesystem" -o ro,noload,nosuid,nodev,noexec -- "/dev/$device" "$target" ;;
    *) echo "Système de fichiers non pris en charge : $filesystem" >&2; exit 1 ;;
esac
