#!/bin/bash
set -Eeuo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
prefix="station-ci-$RANDOM"
temp_dir=$(mktemp -d)
# Appelée par trap ; seuls les conteneurs et volumes créés par ce test sont supprimés.
# shellcheck disable=SC2329
cleanup() {
    docker logs "$prefix-app" 2>/dev/null || true
    docker logs "$prefix-clamav" 2>/dev/null || true
    docker rm -f "$prefix-app" "$prefix-clamav" >/dev/null 2>&1 || true
    docker volume rm "$prefix-history" "$prefix-quarantine" >/dev/null 2>&1 || true
    rm -f "$temp_dir/admin.caddy" "$temp_dir/headers"
    rmdir "$temp_dir"
}
trap cleanup EXIT

# Démarrage réel de la configuration de production, avec une petite base de test sans malware.
docker run -d --name "$prefix-clamav" --read-only --cap-drop ALL \
    --security-opt no-new-privileges:true --tmpfs /tmp:mode=1777 --tmpfs /run/clamav:mode=1777 \
    --mount "type=bind,src=$root/tests/fixtures,dst=/var/lib/clamav,readonly" \
    --entrypoint clamd station-blanche/clamav:test --config-file=/etc/clamav/clamd.conf
for attempt in {1..30}; do
    if docker exec "$prefix-clamav" bash -c "printf 'zPING\\0' | nc -w 1 127.0.0.1 3310 | grep -q PONG"; then break; fi
    [[ "$attempt" != 30 ]] || exit 1
    sleep 1
done

# Les répertoires des volumes doivent être utilisables sans root, même avec un rootfs readonly.
docker run -d --name "$prefix-app" --read-only --cap-drop ALL --security-opt no-new-privileges:true \
    -e SB_CLAMD=127.0.0.1:3310 -p 127.0.0.1:18080:8080 \
    --mount "type=volume,src=$prefix-history,dst=/data" \
    --mount "type=volume,src=$prefix-quarantine,dst=/quarantine" \
    --mount "type=bind,src=$root/tests/fixtures,dst=/media,readonly" station-blanche/app:test
for attempt in {1..30}; do
    if curl -fsS http://127.0.0.1:18080/health/live; then break; fi
    [[ "$attempt" != 30 ]] || exit 1
    sleep 1
done
[[ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/health/ready) == 503 ]]
curl -fsS -D "$temp_dir/headers" http://127.0.0.1:18080/ >/dev/null
grep -qi '^content-security-policy:' "$temp_dir/headers"
curl -fsS http://127.0.0.1:18080/api/status | jq -e '.engine.ready == false and .kpis.analyses == 0'
[[ $(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:18080/api/status) == 405 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/api/scans/invalid/findings) == 400 ]]
docker stop --time 10 "$prefix-app" >/dev/null
[[ $(docker inspect -f '{{.State.ExitCode}}' "$prefix-app") == 0 ]]

hash=$(printf '%s' 'temporary-ci-password-not-deployed' | docker run --rm -i caddy:2 caddy hash-password)
printf 'basic_auth {\n    admin %s\n}\n' "$hash" > "$temp_dir/admin.caddy"
docker run --rm -e STATION_IP=127.0.0.1 \
    --mount "type=bind,src=$root/deploy/Caddyfile,dst=/etc/caddy/Caddyfile,readonly" \
    --mount "type=bind,src=$temp_dir/admin.caddy,dst=/etc/caddy/admin.caddy,readonly" \
    caddy:2 caddy validate --config /etc/caddy/Caddyfile
STATION_IP=127.0.0.1 docker compose config --quiet
echo 'Container runtime checks passed'
