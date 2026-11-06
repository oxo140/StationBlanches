#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $EUID == 0 ]] || { echo 'Exécuter en root.' >&2; exit 1; }
hash=$(awk '$1 == "admin" && $2 ~ /^\$2/ {print $2}' secrets/admin.caddy)
[[ "$hash" =~ ^\$2[aby]\$[0-9][0-9]\$[./A-Za-z0-9]{53}$ ]] || { echo 'Hachage admin absent ou invalide.' >&2; exit 1; }
install -d -m 0700 secrets
umask 077
printf '%s\n' "$hash" > secrets/admin.hash.tmp
chmod 0444 secrets/admin.hash.tmp
mv -f secrets/admin.hash.tmp secrets/admin.hash
echo '[OK] Mot de passe administrateur existant prêt pour la page de connexion.'
