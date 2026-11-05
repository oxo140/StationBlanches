#!/bin/bash
set -Eeuo pipefail
# Le kiosque attend le serveur plutôt que de rester sur une page de connexion refusée au démarrage.
until curl --noproxy '*' -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/health/live >/dev/null 2>&1; do
    sleep 2
done
exec chromium --kiosk --no-first-run http://127.0.0.1:8080/kiosk
