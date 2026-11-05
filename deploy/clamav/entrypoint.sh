#!/bin/bash
set -Eeuo pipefail
umask 022
daemon_pid=""
updater_pid=""
cleanup() {
    trap - EXIT TERM INT
    [[ -z "$daemon_pid" ]] || kill "$daemon_pid" 2>/dev/null || true
    [[ -z "$updater_pid" ]] || kill "$updater_pid" 2>/dev/null || true
    wait || true
}
trap cleanup EXIT TERM INT

update_signatures() {
    if timeout 600 freshclam --config-file=/etc/clamav/freshclam.conf --stdout; then
        local database version
        if [[ -f /var/lib/clamav/daily.cld ]]; then
            database=/var/lib/clamav/daily.cld
        else
            database=/var/lib/clamav/daily.cvd
        fi
        version=$(sigtool --info "$database" | awk '$1 == "Version:" {print $2}')
        if [[ "$version" =~ ^[0-9]+$ ]]; then
            printf '%s %s\n' "$(date +%s)" "$version" > /var/lib/clamav/update-status.tmp
            mv /var/lib/clamav/update-status.tmp /var/lib/clamav/update-status
            echo "[INFO] Signatures vérifiées : $version"
            return 0
        fi
    fi
    echo "[WARN] Mise à jour échouée ; la date de vérification reste inchangée." >&2
    return 1
}

# Le premier téléchargement peut être long. Une ancienne base ne devient jamais fraîche sur simple redémarrage.
update_signatures || true
clamd --config-file=/etc/clamav/clamd.conf &
daemon_pid=$!
(
    delay=21600
    while true; do
        sleep "$delay"
        if update_signatures; then delay=21600; else delay=3600; fi
    done
) &
updater_pid=$!
wait -n "$daemon_pid" "$updater_pid"
# Si un composant s'arrête, Docker doit recréer les deux processus ensemble.
exit 1
