#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
station_ip=$(sed -n 's/^STATION_IP=//p' .env)
systemctl is-active --quiet xrdp
systemctl is-active --quiet xrdp-sesman
python3 - "$station_ip" <<'PY'
import socket,sys
with socket.create_connection((sys.argv[1],3389),timeout=5):
    print('[OK] Services XRDP actifs et port TCP 3389 accessible sur '+sys.argv[1])
PY
echo 'Pour les erreurs de connexion : sudo journalctl -u xrdp -u xrdp-sesman --no-pager -n 60'
