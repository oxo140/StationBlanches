#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $EUID == 0 ]] || { echo 'Exécuter en root.' >&2; exit 1; }
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
sb_apt_install_missing ca-certificates openssl libnss3-tools
desktop_user=$(sb_desktop_user "${1:-}" || true)
[[ -n "$desktop_user" && "$desktop_user" != root ]] || { echo 'Préciser le compte bureau : sudo bash deploy/trust-ca.sh UTILISATEUR' >&2; exit 1; }
user_home=$(getent passwd "$desktop_user" | cut -d: -f6)
certificate=$(mktemp)
trap 'rm -f -- "$certificate"' EXIT
for attempt in {1..30}; do
    if docker compose cp web:/data/caddy/pki/authorities/local/root.crt "$certificate"; then break; fi
    [[ "$attempt" != 30 ]] || exit 1
    sleep 2
done
openssl x509 -in "$certificate" -noout -checkend 86400
install -m 0644 "$certificate" /usr/local/share/ca-certificates/station-blanche.crt
update-ca-certificates
# Couvrir les deux emplacements NSS utilisés selon la version de Chromium.
for db in "$user_home/.pki/nssdb" "$user_home/.local/share/pki/nssdb"; do
    runuser -u "$desktop_user" -- mkdir -p "$db"
    if [[ ! -f "$db/cert9.db" ]]; then
        runuser -u "$desktop_user" -- certutil -N --empty-password -d "sql:$db"
    fi
    if runuser -u "$desktop_user" -- certutil -L -d "sql:$db" -n 'Station Blanche Local CA' >/dev/null 2>&1; then
        runuser -u "$desktop_user" -- certutil -D -d "sql:$db" -n 'Station Blanche Local CA'
    fi
    runuser -u "$desktop_user" -- certutil -A -d "sql:$db" -n 'Station Blanche Local CA' -t 'C,,' -i /usr/local/share/ca-certificates/station-blanche.crt
done
echo '[OK] Certificat HTTPS approuvé sur cette station. Redémarrer Chromium pour appliquer.'
