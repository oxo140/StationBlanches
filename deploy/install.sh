#!/bin/bash
set -Eeuo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ "${1:-}" == --check ]]; then exec bash deploy/check-dependencies.sh; fi
[[ $EUID == 0 ]] || { echo 'Utilisation : sudo bash installation.sh [ADRESSE_IP] [UTILISATEUR_BUREAU]' >&2; exit 1; }
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
sb_platform
sb_require_tty
project=$(pwd)
station_ip=${1:-}
desktop_user=${2:-${SUDO_USER:-}}
echo '=== Station Blanche v2 — installation interactive ==='
missing=()
for package in "${SB_REQUIRED_PACKAGES[@]}"; do
    if sb_installed "$package"; then echo "[OK] $package"; else missing+=("$package"); fi
done
if (( ${#missing[@]} )); then
    sb_ask "Installer les dépendances requises manquantes : ${missing[*]} ?" || { echo 'Installation arrêtée : prérequis requis.' >&2; exit 1; }
    apt-get update
    apt-get install -y "${missing[@]}"
fi
for required in "${SB_REQUIRED_COMMANDS[@]}"; do
    command -v "$required" >/dev/null || { echo "Commande requise absente après installation : $required" >&2; exit 1; }
done
if [[ -z "$station_ip" ]]; then
    if [[ -f .env ]]; then station_ip=$(sed -n 's/^STATION_IP=//p' .env | head -n 1); fi
    if [[ -z "$station_ip" ]]; then station_ip=$(ip -4 -o addr show scope global | awk 'NR==1 {split($4,a,"/");print a[1]}'); fi
    printf 'Adresse IPv4 de la station [%s] : ' "$station_ip" >&3
    IFS= read -r answer <&3
    station_ip=${answer:-$station_ip}
fi
sb_ipv4 "$station_ip" || { echo 'Adresse IPv4 invalide.' >&2; exit 1; }
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$station_ip" || { echo 'Cette adresse ne correspond pas à une interface de la machine.' >&2; exit 1; }

docker_repository() {
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
}
if ! command -v docker >/dev/null; then
    sb_ask 'Installer Docker Engine et les plugins Compose/Buildx (requis) ?' || exit 1
    for conflicting in docker.io docker-compose podman-docker containerd runc; do
        if sb_installed "$conflicting"; then
            echo "Paquet $conflicting déjà présent : résoudre sa migration Docker avant de poursuivre. Aucun paquet supprimé." >&2; exit 1
        fi
    done
    docker_repository
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    plugins=()
    if ! docker compose version >/dev/null 2>&1; then
        if sb_installed docker.io; then plugins+=(docker-compose); else plugins+=(docker-compose-plugin); fi
    fi
    if ! docker buildx version >/dev/null 2>&1; then
        if sb_installed docker.io; then plugins+=(docker-buildx); else plugins+=(docker-buildx-plugin); fi
    fi
    if (( ${#plugins[@]} )); then
        sb_ask "Installer les plugins Docker manquants : ${plugins[*]} ?" || exit 1
        if sb_installed docker.io; then apt-get update; else docker_repository; fi
        apt-get install -y "${plugins[@]}"
    fi
fi
docker compose version
docker buildx version
if ! systemctl is-enabled --quiet docker || ! systemctl is-active --quiet docker; then
    sb_ask 'Activer et démarrer Docker (requis) ?' || exit 1
    systemctl enable --now docker
fi
docker info --format 'Docker prêt : {{.ServerVersion}}'
if ! command -v xfce4-session >/dev/null && ! command -v gnome-session >/dev/null && ! command -v startplasma-x11 >/dev/null && ! command -v startlxqt >/dev/null; then
    if sb_ask 'Installer un bureau Xfce et LightDM ?' N; then
        apt-get update
        apt-get install -y xfce4 lightdm
        echo 'Le bureau sera disponible après ouverture de session / redémarrage.'
    fi
fi
if sb_ask "Installer / vérifier Chromium pour l'écran local en plein écran ?"; then
    if ! sb_installed chromium; then apt-get update; apt-get install -y chromium; fi
    if sb_ask 'Configurer son lancement automatique à la connexion du bureau ?'; then
        printf 'Utilisateur du bureau [%s] : ' "$desktop_user" >&3
        IFS= read -r answer <&3
        desktop_user=${answer:-$desktop_user}
        [[ -n "$desktop_user" && "$desktop_user" != root ]] || { echo 'Un compte bureau non root est requis pour le kiosque.' >&2; exit 1; }
        user_home=$(getent passwd "$desktop_user" | cut -d: -f6)
        [[ -n "$user_home" ]] || { echo 'Utilisateur inconnu.' >&2; exit 1; }
        desktop_group=$(id -gn "$desktop_user")
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
    fi
fi
if sb_ask "Installer / activer un serveur SSH pour l'administration distante ?" N; then
    if ! sb_installed openssh-server; then apt-get update; apt-get install -y openssh-server; fi
    systemctl enable --now ssh
fi
if sb_ask 'Installer / vérifier jq pour les tests automatiques USB et des KPI ?'; then
    if ! sb_installed jq; then apt-get update; apt-get install -y jq; fi
fi
sb_ask 'Configurer le montage USB automatique en lecture seule (requis) ?' || exit 1
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
bash deploy/check-dependencies.sh
if sb_ask 'Construire et démarrer les conteneurs maintenant ?'; then
    docker compose up -d --build
    docker compose ps
    echo 'La première récupération des signatures peut prendre plusieurs minutes.'
    if sb_ask 'Attendre le moteur puis lancer les tests sain / EICAR ?' N; then
        bash deploy/test-antivirus.sh --engine --wait 900
    fi
else
    echo 'Configuration prête. Démarrage ultérieur : sudo docker compose up -d --build'
fi
echo "Installation préparée : $project"
echo 'Interface locale : http://127.0.0.1:8080/?kiosk=1'
echo "Administration : https://$station_ip (admin). Installer le certificat local : voir README.md."
echo 'Retirer puis réinsérer les clés déjà montées par le bureau avant installation.'
