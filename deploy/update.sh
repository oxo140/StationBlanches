#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
install -d -m 0755 /usr/local/lib/station-blanche
install -m 0755 deploy/host/kiosk-launch.sh /usr/local/lib/station-blanche/kiosk-launch.sh
docker compose config --quiet
docker compose build --pull
docker compose pull web
docker compose up -d --force-recreate
docker compose ps
bash deploy/check-web.sh 60
echo "Les volumes d'historique, signatures et quarantaine ont été conservés."
