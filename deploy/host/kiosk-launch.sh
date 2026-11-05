#!/bin/bash
set -Eeuo pipefail
# Un profil séparé empêche Chromium de déléguer la fenêtre à un autre processus.
profile="${XDG_CONFIG_HOME:-$HOME/.config}/station-blanche/chromium"
mkdir -p "$profile"
exec 9>"${profile%/*}/kiosk.lock"
flock -n 9 || exit 0
browser_pid=''
stop() {
    trap - TERM INT HUP
    if [[ -n "$browser_pid" ]]; then
        kill "$browser_pid" 2>/dev/null || true
        wait "$browser_pid" 2>/dev/null || true
    fi
    exit 0
}
trap stop TERM INT HUP
while true; do
    until curl --noproxy '*' -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:8080/health/live >/dev/null 2>&1; do
        sleep 2
    done
    chromium --user-data-dir="$profile" --kiosk --no-first-run --noerrdialogs --disable-background-mode --disable-session-crashed-bubble http://127.0.0.1:8080/kiosk 9>&- &
    browser_pid=$!
    wait "$browser_pid" || true
    browser_pid=''
    # Une fermeture volontaire comme un plantage relance le kiosque.
    sleep 5
done
