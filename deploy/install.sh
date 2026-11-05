#!/bin/bash
set -Eeuo pipefail
umask 077
[[ $EUID == 0 ]] || { echo "Utilisation : sudo bash deploy/install.sh ADRESSE_IP [UTILISATEUR_BUREAU]" >&2; exit 1; }
cd "$(dirname "${BASH_SOURCE[0]}")/.."
project=$(pwd)
ip=${1:?Adresse IPv4 fixe de la station requise}
desktop_user=${2:-${SUDO_USER:-}}
IFS=. read -r -a octets <<< "$ip"
[[ ${#octets[@]} == 4 ]] || { echo "IPv4 invalide" >&2; exit 1; }
for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( 10#$octet <= 255 )) || { echo "IPv4 invalide" >&2; exit 1; }
done
[[ "$ip" != 0.* && "$ip" != 127.* ]] || { echo "Utilisez l'adresse du réseau local" >&2; exit 1; }
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$ip" || { echo "Cette adresse n'appartient pas à la machine" >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
[[ "$ID" == debian && "$VERSION_ID" == 13 ]] || { echo "Debian 13 requis" >&2; exit 1; }
[[ $(dpkg --print-architecture) == amd64 ]] || { echo "Cette version est validée pour amd64" >&2; exit 1; }
apt-get update
apt-get install -y ca-certificates curl udev util-linux exfatprogs
if ! command -v docker >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl --fail --silent --show-error --location https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod 0644 /etc/apt/keyrings/docker.asc
    cat > /etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    chmod 0644 /etc/apt/sources.list.d/docker.sources
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
docker compose version >/dev/null || { echo "Installer le plugin Docker Compose v2 avant de poursuivre" >&2; exit 1; }
systemctl enable --now docker

install -d -m 0755 /usr/local/lib/station-blanche
install -m 0755 deploy/host/prepare-media.sh deploy/host/mount-usb.sh /usr/local/lib/station-blanche/
install -m 0644 deploy/host/*.service /etc/systemd/system/
install -m 0644 deploy/host/99-station-blanche.rules /etc/udev/rules.d/
systemctl daemon-reload
systemctl enable --now station-blanche-media.service
udevadm control --reload-rules
# Les supports déjà montés par le bureau doivent être retirés puis réinsérés.

printf 'STATION_IP=%s\n' "$ip" > .env
install -d -m 0700 secrets
if [[ ! -s secrets/admin.caddy ]]; then
    docker pull caddy:2
    echo "Création de l'accès administrateur (utilisateur : admin)."
    echo "Choisissez un mot de passe d'au moins 16 caractères."
    read -r -s -p 'Mot de passe : ' password; echo
    read -r -s -p 'Confirmation : ' confirm; echo
    [[ ${#password} -ge 16 && "$password" == "$confirm" ]] || { echo "Mot de passe trop court ou différent" >&2; exit 1; }
    hash=$(printf '%s' "$password" | docker run --rm -i caddy:2 caddy hash-password)
    unset password confirm
    [[ "$hash" == '$2'* ]] || { echo "Hachage du mot de passe invalide" >&2; exit 1; }
    printf 'basic_auth {\n    admin %s\n}\n' "$hash" > secrets/admin.caddy
    chmod 0600 secrets/admin.caddy
fi
docker compose config --quiet
docker compose up -d --build

if [[ -n "$desktop_user" && "$desktop_user" != root ]]; then
    user_home=$(getent passwd "$desktop_user" | cut -d: -f6)
    [[ -n "$user_home" ]] || { echo "Utilisateur bureau inconnu" >&2; exit 1; }
    apt-get install -y chromium
    install -d -o "$desktop_user" -g "$(id -gn "$desktop_user")" -m 0755 "$user_home/.config/autostart"
    cat > "$user_home/.config/autostart/station-blanche.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Station Blanche
Exec=chromium --kiosk --no-first-run http://127.0.0.1:8080/?kiosk=1
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
    chown "$desktop_user:$(id -gn "$desktop_user")" "$user_home/.config/autostart/station-blanche.desktop"
    chmod 0644 "$user_home/.config/autostart/station-blanche.desktop"
fi
echo "Installation préparée : $project"
echo "Interface locale : http://127.0.0.1:8080/?kiosk=1"
echo "Administration : https://$ip (utilisateur admin)"
echo "Installer l'autorité de certification locale : voir README.md."
echo "La première récupération des signatures peut prendre plusieurs minutes."
