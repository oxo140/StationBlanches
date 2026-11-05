#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
temp_dir=$(mktemp -d)
project="station-web-ci-$RANDOM"
export STATION_IP=127.0.0.1
export SB_COMPOSE_TEST_MEDIA="$temp_dir/media"
export SB_COMPOSE_TEST_AUTH="$temp_dir/admin.caddy"
compose() { docker compose -p "$project" -f compose.yaml -f tests/compose-web.yaml "$@"; }
# Appelée par trap ; ce projet et ses volumes sont dédiés à ce test.
# shellcheck disable=SC2329
cleanup() {
    compose logs --tail=50 app web || true
    compose down --volumes --remove-orphans || true
    if mountpoint -q "$temp_dir/media"; then sudo umount "$temp_dir/media"; fi
    rm -f "$temp_dir/admin.caddy" "$temp_dir/ca.crt" "$temp_dir/headers"
    rmdir "$temp_dir/media" "$temp_dir"
}
trap cleanup EXIT
mkdir "$temp_dir/media"
sudo mount --bind "$temp_dir/media" "$temp_dir/media"
sudo mount --make-rshared "$temp_dir/media"
hash=$(printf '%s' 'temporary-ci-password-not-deployed' | docker run --rm -i caddy:2 caddy hash-password)
printf 'basic_auth {\n    admin %s\n}\n' "$hash" > "$temp_dir/admin.caddy"
compose config --quiet
compose up -d --no-build
for attempt in {1..60}; do
    if curl --noproxy '*' -fsS --max-time 3 http://127.0.0.1:8080/health/live >/dev/null; then break; fi
    [[ "$attempt" != 60 ]] || exit 1
    sleep 1
done
curl --noproxy '*' -fsS -D "$temp_dir/headers" http://127.0.0.1:8080/ | grep -q 'Station Blanche'
grep -qi '^content-security-policy:' "$temp_dir/headers"
[[ $(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health/ready) == 503 ]]
app_id=$(compose ps -q app)
web_id=$(compose ps -q web)
# La publication du kiosque appartient au proxy, pas au réseau interne de l'application.
[[ -z $(docker port "$app_id" 8080) ]]
[[ $(docker port "$web_id" 8080) == 127.0.0.1:8080 ]]
docker inspect "$app_id" | jq -e '.[0].NetworkSettings.Networks | length == 2'
compose cp web:/data/caddy/pki/authorities/local/root.crt "$temp_dir/ca.crt"
for attempt in {1..30}; do
    if status=$(curl --noproxy '*' --cacert "$temp_dir/ca.crt" -s -o /dev/null -w '%{http_code}' https://127.0.0.1/); then break; fi
    [[ "$attempt" != 30 ]] || exit 1
    sleep 1
done
[[ "$status" == 401 ]]
curl --noproxy '*' --cacert "$temp_dir/ca.crt" --user admin:temporary-ci-password-not-deployed -fsS https://127.0.0.1/ | grep -q 'Station Blanche'
echo 'Production Compose local kiosk and authenticated HTTPS checks passed'
