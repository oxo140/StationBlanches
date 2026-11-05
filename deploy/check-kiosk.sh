#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
desktop_user=$(sb_desktop_user "${1:-}" || true)
[[ -n "$desktop_user" && "$desktop_user" != root ]] || { echo 'Préciser le compte bureau.' >&2; exit 1; }
uid=$(id -u "$desktop_user")
file="/run/user/$uid/station-blanche/kiosk-status.json"
[[ -r "$file" ]] || { echo '[EN ATTENTE] Aucune vérification du kiosque. Connecter la session graphique après installation.'; exit 1; }
jq . "$file"
now=$(date +%s)
jq -e --argjson now "$now" '.state == "visible" and (.checked_at <= $now) and ($now - .checked_at < 15)' "$file" >/dev/null || {
    echo '[À VÉRIFIER] La page Station Blanche ne possède pas de confirmation récente du navigateur.'; exit 1;
}
echo '[OK] Page Station Blanche chargée et onglet actif confirmés par Chromium.'
