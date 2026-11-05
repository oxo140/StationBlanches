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
missing=()
for package in git ca-certificates; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) != 'install ok installed' ]]; then missing+=("$package"); fi
done
if (( ${#missing[@]} )); then
    printf 'Installer les prérequis de téléchargement (%s) ? [O/n] : ' "${missing[*]}" >&3
    IFS= read -r answer <&3
    case "${answer,,}" in ''|o|oui|y|yes) ;; *) echo 'Installation annulée.'; exit 1 ;; esac
    apt-get update
    apt-get install -y "${missing[@]}"
fi
[[ ! -L "$target" ]] || { echo 'Le répertoire cible ne doit pas être un lien symbolique.' >&2; exit 1; }
if [[ -e "$target" ]]; then
    [[ -d "$target/.git" ]] || { echo "$target existe et ne contient pas le dépôt attendu." >&2; exit 1; }
    [[ $(git -C "$target" remote get-url origin) == "$repo" ]] || { echo 'Dépôt existant différent : arrêt.' >&2; exit 1; }
    [[ $(git -C "$target" branch --show-current) == "$branch" ]] || { echo 'Branche existante différente : arrêt.' >&2; exit 1; }
    [[ -z $(git -C "$target" status --porcelain) ]] || { echo 'Modifications locales présentes : arrêt pour les conserver.' >&2; exit 1; }
    printf 'Mettre à jour les sources dans %s ? [O/n] : ' "$target" >&3
    IFS= read -r answer <&3
    case "${answer,,}" in ''|o|oui|y|yes) git -C "$target" pull --ff-only ;; n|non|no) ;; *) echo 'Réponse invalide.' >&2; exit 1 ;; esac
else
    git clone --depth 1 --branch "$branch" "$repo" "$target"
fi
exec bash "$target/installation.sh" "$@"
