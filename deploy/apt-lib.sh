#!/bin/bash
# Les paquets installés sont conservés ; les index ne sont rafraîchis qu'une fois si nécessaire.
SB_APT_REFRESHED=0
sb_apt_refresh() {
    if [[ "$SB_APT_REFRESHED" == 0 ]]; then
        apt-get -o APT::Update::Error-Mode=any update || { echo '[ERREUR APT] Rafraîchissement des sources impossible ; installation arrêtée.' >&2; return 1; }
        SB_APT_REFRESHED=1
    fi
}

sb_apt_candidate() {
    LC_ALL=C apt-cache policy "$1" | awk '$1=="Candidate:" && $2!="(none)" {found=1} END{exit !found}'
}

sb_apt_install_missing() {
    local package
    local -a missing=()
    for package in "$@"; do
        if sb_installed "$package"; then echo "[OK] $package déjà installé."; else missing+=("$package"); fi
    done
    if (( ${#missing[@]} == 0 )); then return 0; fi
    sb_apt_refresh || return 1
    for package in "${missing[@]}"; do
        sb_apt_candidate "$package" || { echo "[ERREUR SOURCES APT] Aucun candidat pour $package. Vérifier les dépôts Debian 13 / main et le diagnostic réseau." >&2; return 1; }
    done
    echo "[INSTALLATION] ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# Reconnaît les sources actives, y compris le format deb822 et les fichiers désactivés.
sb_apt_docker_file_enabled() {
    [[ -f "$1" ]] || return 1
    case "$1" in
        *.sources)
            awk 'BEGIN{RS=""}
                {
                    delete f; key=""; n=split($0, lines, "\n")
                    for(i=1;i<=n;i++) {
                        line=lines[i]
                        if(line~/^[[:space:]]*#/) continue
                        if(line~/^[[:space:]]/ && key!="") {f[key]=f[key] " " line;continue}
                        p=index(line,":")
                        if(p>0) {key=tolower(substr(line,1,p-1));value=substr(line,p+1);sub(/^[[:space:]]+/,"",value);f[key]=value}
                    }
                    if(tolower(f["enabled"])~/^no[[:space:]]*$/) next
                    if(f["types"]~/(^|[[:space:]])deb([[:space:]]|$)/ && f["uris"]~/(^|[[:space:]])https:\/\/download[.]docker[.]com\/linux\/debian\/?([[:space:]]|$)/) found=1
                }
                END{exit !found}
            ' "$1"
            ;;
        *)
            awk '{sub(/[[:space:]]*#.*/,"")}
                /^[[:space:]]*deb[[:space:]]/ && /https:\/\/download[.]docker[.]com\/linux\/debian\/?([[:space:]]|$)/ {found=1}
                END{exit !found}
            ' "$1"
            ;;
    esac
}

sb_apt_docker_sources() {
    local file
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        if sb_apt_docker_file_enabled "$file"; then printf '%s\n' "$file"; fi
    done
}

sb_desktop_user() {
    local requested=${1:-${SUDO_USER:-}} uid_min
    local -a candidates
    if [[ -n "$requested" && "$requested" != root ]]; then
        getent passwd "$requested" | awk -F: '$3>0 && $7!~/(nologin|false)$/ {print $1}'
        return
    fi
    uid_min=$(awk '$1=="UID_MIN" {print $2;exit}' /etc/login.defs)
    uid_min=${uid_min:-1000}
    mapfile -t candidates < <(getent passwd | awk -F: -v minimum="$uid_min" '$3>=minimum && $3<65534 && $7!~/(nologin|false)$/ {print $1}')
    if (( ${#candidates[@]} == 1 )); then printf '%s\n' "${candidates[0]}"; fi
}
