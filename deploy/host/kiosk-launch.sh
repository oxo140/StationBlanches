#!/bin/bash
set -Eeuo pipefail
profile="${XDG_CONFIG_HOME:-$HOME/.config}/station-blanche/chromium"
mkdir -p "$profile"
exec 9>"${profile%/*}/kiosk.lock"
flock -n 9 || exit 0
scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if ! python3 "$scripts/desktop-session.py"; then
    echo '[À VÉRIFIER] Certains réglages du bureau ont échoué. Le kiosque démarre tout de même.' >&2
fi
# Le pipe CDP reste privé au superviseur ; aucun port de débogage n'est ouvert.
supervisor_pid=''
stop() {
    trap - TERM INT HUP
    if [[ -n "$supervisor_pid" ]]; then
        kill "$supervisor_pid" 2>/dev/null || true
        wait "$supervisor_pid" 2>/dev/null || true
    fi
    exit 0
}
trap stop TERM INT HUP
while true; do
    python3 "$scripts/kiosk-supervisor.py" "$profile" &
    supervisor_pid=$!
    wait "$supervisor_pid" || true
    supervisor_pid=''
    sleep 5
done
