#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash deploy/desktop.sh
bash deploy/rdp.sh
bash deploy/prepare-auth.sh
docker compose config --quiet
docker compose build --pull
docker compose pull web
docker compose up -d --force-recreate
docker compose ps
bash deploy/check-web.sh 60
bash deploy/trust-ca.sh
echo "Les volumes d'historique, signatures et quarantaine ont été conservés."
