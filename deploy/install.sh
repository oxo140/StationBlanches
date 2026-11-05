#!/bin/bash
set -Eeuo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ "${1:-}" == --check ]]; then exec bash deploy/check-dependencies.sh; fi
if [[ "${1:-}" == --network-check ]]; then exec bash deploy/network.sh --check; fi
if [[ "${1:-}" == --network ]]; then exec bash deploy/network.sh; fi
desktop_requested=''
if [[ "${1:-}" == --desktop-user ]]; then
    [[ $# == 2 ]] || { echo 'Utilisation : sudo bash installation.sh --desktop-user UTILISATEUR' >&2; exit 2; }
    desktop_requested=$2
    shift 2
fi
[[ $EUID == 0 ]] || { echo 'Utilisation : sudo bash installation.sh [ADRESSE_IP] [UTILISATEUR_BUREAU]' >&2; exit 1; }
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/network-lib.sh
source deploy/network-lib.sh
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
sb_platform
sb_require_tty
project=$(pwd)
station_ip=${1:-}
desktop_user=$(sb_desktop_user "${desktop_requested:-${2:-}}" || true)
[[ -n "$desktop_user" && "$desktop_user" != root ]] || {
    echo 'Impossible de choisir un compte bureau non root sans ambiguïté. Lancer via sudo depuis ce compte, ou préciser : sudo bash installation.sh --desktop-user UTILISATEUR.' >&2
    exit 1
}
user_home=$(getent passwd "$desktop_user" | cut -d: -f6)
desktop_group=$(id -gn "$desktop_user")
echo '=== Station Blanche v2 — installation automatique ==='
echo "[OK] Compte bureau : $desktop_user"
# Seule option demandée : passer du réseau actuel (DHCP par défaut) à une IPv4 manuelle.
bash deploy/network.sh --install
sb_apt_install_missing "${SB_REQUIRED_PACKAGES[@]}"
for required in "${SB_REQUIRED_COMMANDS[@]}"; do
    command -v "$required" >/dev/null || { echo "Commande requise absente après installation : $required" >&2; exit 1; }
done
if [[ -z "$station_ip" ]]; then
    primary_interface=$(sb_default_interface)
    station_ip=$(ip -4 -o addr show dev "$primary_interface" scope global | awk 'NR==1 {split($4,a,"/");print a[1]}')
fi
sb_ipv4 "$station_ip" || { echo 'Aucune IPv4 valide détectée. Vérifier le bail DHCP et la route par défaut.' >&2; exit 1; }
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$station_ip" || { echo 'Adresse demandée non présente sur la machine.' >&2; exit 1; }
echo "[OK] IPv4 détectée pour la station : $station_ip (aucune saisie nécessaire en DHCP)."

docker_repository() {
    local key_tmp existing
    existing=$(sb_apt_docker_sources)
    if [[ -n "$existing" ]]; then
        echo "[OK] Sources Docker déjà présentes : $existing"
        sb_apt_refresh
        sb_apt_candidate docker-ce || { echo 'Source Docker active mais paquet docker-ce indisponible : vérifier sa suite trixie, sa clé et les erreurs APT. Aucune source dupliquée.' >&2; return 1; }
        return 0
    fi
    [[ ! -e /etc/apt/sources.list.d/station-blanche-docker.sources ]] || { echo 'Fichier station-blanche-docker.sources préexistant non actif : vérifier ce fichier avant de continuer.' >&2; return 1; }
    sb_network_check
    install -m 0755 -d /etc/apt/keyrings
    if [[ -s /etc/apt/keyrings/docker.asc ]] && grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' /etc/apt/keyrings/docker.asc; then
        echo '[OK] Clé Docker déjà présente.'
    else
        key_tmp=$(mktemp /etc/apt/keyrings/.docker.XXXXXXXX)
        if ! sb_fetch https://download.docker.com/linux/debian/gpg "$key_tmp"; then rm -f -- "$key_tmp"; return 1; fi
        if ! grep -q '^-----BEGIN PGP PUBLIC KEY BLOCK-----' "$key_tmp"; then rm -f -- "$key_tmp"; echo 'Clé Docker reçue invalide ; ancienne clé conservée.' >&2; return 1; fi
        mv -f -- "$key_tmp" /etc/apt/keyrings/docker.asc
        chmod 0644 /etc/apt/keyrings/docker.asc
    fi
    cat > /etc/apt/sources.list.d/station-blanche-docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    chmod 0644 /etc/apt/sources.list.d/station-blanche-docker.sources
    SB_APT_REFRESHED=0
    sb_apt_refresh
}
if ! command -v docker >/dev/null; then
    for conflicting in docker.io docker-compose podman-docker containerd runc; do
        if sb_installed "$conflicting"; then echo "Paquet $conflicting déjà présent mais commande Docker absente : réparer cette installation avant de poursuivre. Aucun paquet supprimé." >&2; exit 1; fi
    done
    docker_repository
    sb_apt_install_missing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    echo '[OK] Docker déjà présent : moteur existant conservé.'
    plugins=()
    if ! docker compose version >/dev/null 2>&1; then
        if sb_installed docker.io; then plugins+=(docker-compose); else plugins+=(docker-compose-plugin); fi
    fi
    if ! docker buildx version >/dev/null 2>&1; then
        if sb_installed docker.io; then plugins+=(docker-buildx); else plugins+=(docker-buildx-plugin); fi
    fi
    if (( ${#plugins[@]} )); then
        if ! sb_installed docker.io; then docker_repository; fi
        sb_apt_install_missing "${plugins[@]}"
    fi
fi
docker compose version
docker buildx version
systemctl enable --now docker
docker info --format 'Docker prêt : {{.ServerVersion}}'
has_desktop=0
for session in xfce4-session gnome-session startplasma-x11 startplasma-wayland startlxqt lxsession mate-session cinnamon-session; do
    if command -v "$session" >/dev/null; then has_desktop=1; break; fi
done
if (( ! has_desktop )); then sb_apt_install_missing xfce4 lightdm; else echo '[OK] Bureau existant conservé.'; fi
sb_apt_install_missing chromium openssh-server jq
if ! command -v chromium >/dev/null; then
    echo '[RÉPARATION] Paquet Chromium présent mais commande absente.'
    sb_apt_refresh
    DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y chromium
fi
chromium --version
install -d -o "$desktop_user" -g "$desktop_group" -m 0755 "$user_home/.config/autostart"
cat > "$user_home/.config/autostart/station-blanche.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Station Blanche
Exec=chromium --kiosk --no-first-run http://127.0.0.1:8080/?kiosk=1
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
chown "$desktop_user:$desktop_group" "$user_home/.config/autostart/station-blanche.desktop"
chmod 0644 "$user_home/.config/autostart/station-blanche.desktop"
systemctl enable --now ssh
install -d -m 0755 /usr/local/lib/station-blanche
install -m 0755 deploy/host/prepare-media.sh deploy/host/mount-usb.sh /usr/local/lib/station-blanche/
install -m 0644 deploy/host/*.service /etc/systemd/system/
install -m 0644 deploy/host/99-station-blanche.rules /etc/udev/rules.d/
systemctl daemon-reload
systemctl enable --now station-blanche-media.service
udevadm control --reload-rules
printf 'STATION_IP=%s\n' "$station_ip" > .env
install -d -m 0700 secrets
if [[ ! -s secrets/admin.caddy ]]; then
    docker pull caddy:2
    echo 'Créer le mot de passe HTTPS (admin, 16 caractères minimum).'
    while true; do
        IFS= read -r -s -p 'Mot de passe : ' password <&3; printf '\n' >&3
        IFS= read -r -s -p 'Confirmation : ' confirm <&3; printf '\n' >&3
        if [[ ${#password} -ge 16 && "$password" == "$confirm" ]]; then break; fi
        echo 'Mot de passe trop court ou confirmation différente. Réessayez.'
    done
    hash=$(printf '%s' "$password" | docker run --rm -i caddy:2 caddy hash-password)
    unset password confirm
    [[ "$hash" == \$2* ]] || { echo 'Hachage invalide.' >&2; exit 1; }
    printf 'basic_auth {\n    admin %s\n}\n' "$hash" > secrets/admin.caddy
    chmod 0600 secrets/admin.caddy
else
    echo '[OK] Mot de passe HTTPS existant conservé.'
fi
docker compose config --quiet
docker compose up -d --build
docker compose ps
bash deploy/check-dependencies.sh
echo 'Attente des signatures et tests automatiques sain / EICAR (jusqu’à 15 minutes au premier démarrage).'
bash deploy/test-antivirus.sh --engine --wait 900
echo "Installation terminée : $project"
echo 'Interface locale : http://127.0.0.1:8080/?kiosk=1'
echo "Administration : https://$station_ip (admin). Installer le certificat local : voir README.md."
echo 'Retirer puis réinsérer les clés déjà montées par le bureau avant installation.'
