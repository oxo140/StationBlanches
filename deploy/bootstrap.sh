#!/bin/bash
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Lancer ce script avec sudo.' >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 && $(dpkg --print-architecture) == amd64 ]] || {
    echo 'Debian 13 amd64 requis.' >&2; exit 1;
}
if ! { exec 3<>/dev/tty; } 2>/dev/null; then echo 'Un terminal interactif est requis.' >&2; exit 1; fi
repo=https://github.com/oxo140/StationBlanches.git
branch=codex/v2-rust-docker
target=/opt/station-blanche
# Diagnostic initial sans dépendre de curl, ni télécharger un outil DNS.
if command -v ping >/dev/null; then
    if ping -4 -n -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then echo '[OK] Ping Google DNS 8.8.8.8.'; else echo '[INFO] Ping sans réponse ; ICMP peut être filtré.'; fi
fi
for domain in deb.debian.org github.com; do
    if ! timeout 5 getent ahostsv4 "$domain" >/dev/null; then
        echo "[ERREUR DNS] $domain ne peut pas être résolu. Corriger les DNS DHCP dans Debian avant de télécharger les sources." >&2
        echo 'Si les sources sont déjà présentes : sudo bash /opt/station-blanche/deploy/network.sh' >&2
        echo 'Sinon utiliser les paramètres réseau du bureau ou sudo nmtui (si installé).' >&2
        exit 1
    fi
done
missing=()
for package in git ca-certificates; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) != 'install ok installed' ]]; then missing+=("$package"); fi
done
if (( ${#missing[@]} )); then
    printf '[INSTALLATION] Prérequis manquants : %s\n' "${missing[*]}"
    apt-get -o APT::Update::Error-Mode=any update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
fi
[[ ! -L "$target" ]] || { echo 'Le répertoire cible ne doit pas être un lien symbolique.' >&2; exit 1; }
if [[ -e "$target" ]]; then
    [[ -d "$target/.git" ]] || { echo "$target existe et ne contient pas le dépôt attendu." >&2; exit 1; }
    [[ $(git -C "$target" remote get-url origin) == "$repo" ]] || { echo 'Dépôt existant différent : arrêt.' >&2; exit 1; }
    [[ $(git -C "$target" branch --show-current) == "$branch" ]] || { echo 'Branche existante différente : arrêt.' >&2; exit 1; }
    [[ -z $(git -C "$target" status --porcelain) ]] || { echo 'Modifications locales présentes : arrêt pour les conserver.' >&2; exit 1; }
    echo "[OK] Sources déjà présentes : $target ; mise à jour sans recréer le dépôt."
    git -C "$target" pull --ff-only
else
    git clone --depth 1 --branch "$branch" "$repo" "$target"
fi
exec bash "$target/installation.sh" "$@"
