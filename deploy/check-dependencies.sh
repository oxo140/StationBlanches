#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/network-lib.sh
source deploy/network-lib.sh
failed=0
check() {
    local label=$1
    shift
    if "$@"; then printf '[OK] %s\n' "$label"; else printf '[MANQUANT] %s\n' "$label"; failed=1; fi
}
check 'Debian 13 amd64' sb_platform
check 'Internet IPv4, DNS et HTTPS' sb_network_check
for package in "${SB_REQUIRED_PACKAGES[@]}"; do check "Paquet $package" sb_installed "$package"; done
for command in "${SB_REQUIRED_COMMANDS[@]}"; do
    if command -v "$command" >/dev/null; then
        printf '[OK] Commande %s\n' "$command"
    else
        printf '[MANQUANT] Commande %s\n' "$command"; failed=1
    fi
done
check 'Docker CLI' docker --version
check 'Docker Compose v2' docker compose version
check 'Docker Buildx' docker buildx version
check 'Démon Docker accessible' docker info --format '{{.ServerVersion}}'
if command -v chromium >/dev/null; then echo '[OPTIONNEL OK] Chromium'; else echo '[OPTIONNEL ABSENT] Chromium (kiosque)'; fi
if command -v jq >/dev/null; then echo '[OPTIONNEL OK] jq'; else echo '[OPTIONNEL ABSENT] jq (vérification USB automatisée)'; fi
if command -v xfce4-session >/dev/null; then echo '[OPTIONNEL OK] Xfce'; else echo '[OPTIONNEL ABSENT] Xfce (un autre bureau convient aussi)'; fi
if [[ -f .env && -s secrets/admin.caddy ]]; then
    check 'Configuration Docker Compose' docker compose config --quiet
    if docker compose ps --status running --services 2>/dev/null | grep -qx app; then
        check 'Binaire Rust dans le conteneur' docker compose exec -T app /usr/bin/test -x /usr/local/bin/station-blanche
        check 'Client HTTP du conteneur' docker compose exec -T app curl --version
    else
        echo '[À DÉMARRER] Application Docker'
    fi
    if docker compose ps --status running --services 2>/dev/null | grep -qx clamav; then
        check 'ClamAV dans le conteneur' docker compose exec -T clamav clamd --version
        check 'FreshClam dans le conteneur' docker compose exec -T clamav freshclam --version
        check 'Client de test antivirus' docker compose exec -T clamav clamdscan --version
    else
        echo '[À DÉMARRER] Antivirus Docker'
    fi
else
    echo '[À CONFIGURER] Adresse IP et accès HTTPS (normal avant installation)'
fi
if (( failed )); then
    echo '[ÉCHEC] Dépendances requises manquantes ou Docker inaccessible. Relancer sudo bash installation.sh pour les installer.'
    exit 1
fi
echo '[OK] Toutes les dépendances hôte requises sont disponibles. Rust et ClamAV sont fournis par Docker.'
