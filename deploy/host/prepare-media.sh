#!/bin/bash
set -Eeuo pipefail
root=/srv/station-blanche/media
install -d -m 0755 "$root"
mountpoint -q "$root" || mount --bind "$root" "$root"
mount --make-rshared "$root"
