#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
limit=${1:-60}
if [[ ! "$limit" =~ ^[1-9][0-9]{0,3}$ ]]; then echo 'Délai de contrôle web invalide.' >&2; exit 2; fi
if (( limit>3600 )); then echo 'Délai de contrôle web invalide.' >&2; exit 2; fi
deadline=$((SECONDS+limit))
echo 'Vérification de la page locale http://127.0.0.1:8080/…'
while (( SECONDS<deadline )); do
    if curl --noproxy '*' --fail --silent --show-error --connect-timeout 2 --max-time 4 http://127.0.0.1:8080/health/live >/dev/null 2>&1; then
        if curl --noproxy '*' --fail --silent --show-error --max-time 4 http://127.0.0.1:8080/ >/dev/null; then
            echo '[OK] Page web accessible depuis la machine hôte. Le moteur antivirus peut encore initialiser ses signatures.'
            exit 0
        fi
    fi
    sleep 2
done
echo '[ÉCHEC] La page locale ne répond pas. État et journaux des conteneurs :' >&2
docker compose ps -a || true
docker compose logs --tail=60 app web clamav || true
echo 'Diagnostic : sudo docker compose ps -a ; sudo docker compose logs --tail=80 app web clamav' >&2
exit 1
