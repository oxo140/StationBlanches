#!/bin/bash
# Fonctions partagées ; ce fichier n'exécute aucune installation lorsqu'il est sourcé.
# Lues également par les scripts qui sourcent ce fichier.
# shellcheck disable=SC2034
SB_REQUIRED_PACKAGES=(ca-certificates curl git udev util-linux exfatprogs iproute2 iputils-ping coreutils)
# shellcheck disable=SC2034
SB_REQUIRED_COMMANDS=(curl git udevadm mount umount mountpoint findmnt blkid lsblk ip ping getent realpath sha256sum base64 timeout systemctl)

sb_installed() {
    [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null) == 'install ok installed' ]]
}

sb_platform() {
    # shellcheck source=/dev/null
    source /etc/os-release
    [[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || {
        echo '[ERREUR] Debian 13 (dont 13.7) requis.' >&2; return 1;
    }
    [[ $(dpkg --print-architecture) == amd64 ]] || {
        echo '[ERREUR] Architecture amd64 requise.' >&2; return 1;
    }
}

sb_ask() {
    local question=$1 default=${2:-O} answer
    while true; do
        printf '%s [%s] : ' "$question" "$([[ "$default" == O ]] && printf 'O/n' || printf 'o/N')" >&3
        IFS= read -r answer <&3 || return 1
        answer=${answer:-$default}
        case "${answer,,}" in
            o|oui|y|yes) return 0 ;;
            n|non|no) return 1 ;;
            *) printf 'Répondre oui ou non.\n' >&3 ;;
        esac
    done
}

sb_require_tty() {
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then
        echo '[ERREUR] Ouvrir un terminal interactif. Pour un diagnostic sans modification : bash installation.sh --check' >&2
        return 1
    fi
}

sb_ipv4() {
    local value=$1 octet
    local -a octets
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a octets <<< "$value"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
    (( 10#${octets[0]} < 224 )) || return 1
    [[ "$value" != 0.* && "$value" != 127.* ]]
}
