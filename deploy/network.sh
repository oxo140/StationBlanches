#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/network-lib.sh
source deploy/network-lib.sh

if [[ "${1:-}" == --check ]]; then sb_network_check; exit $?; fi
if [[ "${1:-}" == --activate-nm ]]; then
    [[ $EUID == 0 && ( $# == 3 || $# == 4 ) && "$2" =~ ^[a-fA-F0-9-]+$ && "$3" =~ ^[a-zA-Z0-9_.-]+$ ]] || exit 1
    marker=${4:-}
    if [[ -n "$marker" ]]; then [[ "$marker" =~ ^/run/station-blanche-network-confirm\.[a-zA-Z0-9]+$ && -f "$marker" && ! -L "$marker" && -O "$marker" ]] || exit 1; fi
    if nmcli --wait 30 connection up uuid "$2" ifname "$3" && sb_network_check; then
        if [[ -n "$marker" ]]; then printf 'Yes\n' > "$marker"; fi
        exit 0
    fi
    if [[ -n "$marker" ]]; then printf 'No\n' > "$marker"; fi
    exit 1
fi
install_mode=0
if [[ "${1:-}" == --install ]]; then install_mode=1; fi
[[ $EUID == 0 ]] || { echo 'Utilisation : sudo bash deploy/network.sh [--check]' >&2; exit 1; }
sb_platform
sb_require_tty
if ! command -v ip >/dev/null; then
    echo 'iproute2 absent : configuration IPv4 différée. Vérification DNS / HTTPS avant installation de cette dépendance.'
    sb_network_check
    exit $?
fi

if (( install_mode )); then
    echo '[RÉSEAU] Configuration actuelle conservée par défaut (DHCP sur une installation standard).'
    if ! sb_ask 'Souhaitez-vous passer en IPv4 manuelle ?' N; then sb_network_check; exit $?; fi
fi

while true; do
    interface=$(sb_default_interface)
    ip -br -4 address show
    if (( install_mode )) && [[ -n "$interface" ]]; then
        echo "[OK] Interface détectée : $interface"
    else
    printf 'Interface à utiliser [%s] : ' "$interface" >&3
    IFS= read -r answer <&3
    interface=${answer:-$interface}
    fi
    [[ "$interface" =~ ^[a-zA-Z0-9_.-]+$ && "$interface" != lo ]] || { echo 'Interface invalide.' >&2; exit 1; }
    ip link show dev "$interface" >/dev/null || exit 1
    if (( install_mode )); then choice=3; else
    echo '1) Conserver la configuration actuelle (DHCP si déjà actif) — défaut'
    echo '2) Passer en DHCP automatique'
    echo '3) Définir une IPv4 manuelle'
    echo '4) Modifier uniquement les DNS, en conservant le mode IP actuel'
    printf 'Choix [1] : ' >&3
    IFS= read -r choice <&3
    choice=${choice:-1}
    fi
    address=''; gateway=''; dns=''
    case "$choice" in
        1)
            if sb_network_check; then exit 0; fi
            sb_ask 'Corriger la configuration réseau maintenant ?' || exit 1
            continue
            ;;
        2) mode=auto ;;
        3)
            mode=manual
            printf 'Adresse IPv4 avec préfixe (exemple 192.168.1.50/24) : ' >&3
            IFS= read -r address <&3
            sb_cidr4 "$address" || { echo 'Adresse / préfixe invalide.' >&2; continue; }
            printf 'Passerelle IPv4 : ' >&3
            IFS= read -r gateway <&3
            sb_ipv4 "$gateway" || { echo 'Passerelle invalide.' >&2; continue; }
            ;;
        4) mode=dns ;;
        *) echo 'Choix invalide.'; continue ;;
    esac
    printf 'DNS IPv4 séparés par des espaces (ex. 1.1.1.1 8.8.8.8%s) : ' "$([[ "$mode" == auto ]] && printf ', vide = DNS DHCP' || true)" >&3
    IFS= read -r dns <&3
    if [[ -n "$dns" ]]; then
        sb_dns4 "$dns" || { echo 'Liste DNS invalide (1 à 3 adresses IPv4).' >&2; continue; }
    elif [[ "$mode" != auto ]]; then
        echo 'Des DNS sont requis pour une adresse manuelle ou une correction DNS.' >&2; continue
    fi
    echo "Interface : $interface ; mode : $mode ; adresse : ${address:-inchangée / DHCP} ; passerelle : ${gateway:-inchangée / DHCP} ; DNS : ${dns:-DHCP}."
    echo 'Le changement peut couper cette connexion. Sans confirmation, retour à la configuration précédente après 180 secondes.'
    if (( ! install_mode )); then sb_ask 'Appliquer cette configuration ?' N || continue; fi

    uuid=''
    if command -v nmcli >/dev/null; then uuid=$(nmcli -g GENERAL.CON-UUID device show "$interface" 2>/dev/null || true); fi
    if [[ "$uuid" =~ ^[a-fA-F0-9]{8}-[a-fA-F0-9-]+$ ]]; then
        name="Station-Blanche-$interface-$(date +%s)-$RANDOM"
        nmcli connection clone uuid "$uuid" "$name"
        clone=$(nmcli -g connection.uuid connection show id "$name")
        nmcli connection modify uuid "$clone" connection.autoconnect no
        if [[ "$mode" == manual ]]; then
            nmcli connection modify uuid "$clone" ipv4.method manual ipv4.addresses "$address" ipv4.gateway "$gateway"
        elif [[ "$mode" == auto ]]; then
            nmcli connection modify uuid "$clone" ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.ignore-auto-routes no
        fi
        if [[ -n "$dns" ]]; then
            nmcli connection modify uuid "$clone" ipv4.ignore-auto-dns yes ipv4.dns "$dns" ipv4.dns-priority -42
        else
            nmcli connection modify uuid "$clone" ipv4.ignore-auto-dns no ipv4.dns '' ipv4.dns-priority 0
        fi
        if (( install_mode )); then
            marker=$(mktemp /run/station-blanche-network-confirm.XXXXXXXX)
            if sb_nm_auto_confirm "$marker" | LC_ALL=C nmcli device checkpoint --timeout 180 "$interface" -- bash "$PWD/deploy/network.sh" --activate-nm "$clone" "$interface" "$marker"; then :; fi
            rm -f -- "$marker"
        else
            echo 'Après le diagnostic, saisir Yes dans la confirmation NetworkManager pour conserver la nouvelle configuration.'
            if LC_ALL=C nmcli device checkpoint --timeout 180 "$interface" -- bash "$PWD/deploy/network.sh" --activate-nm "$clone" "$interface" <&3; then :; fi
        fi
        active=$(nmcli -g GENERAL.CON-UUID device show "$interface" 2>/dev/null || true)
        if [[ "$active" == "$clone" ]] && sb_network_check; then
            nmcli connection modify uuid "$clone" connection.autoconnect yes connection.autoconnect-priority 999
            echo "[OK] Configuration conservée. Profil précédent disponible : $uuid"
            exit 0
        fi
        nmcli --wait 30 connection up uuid "$uuid" ifname "$interface" || true
        nmcli connection delete uuid "$clone"
        echo 'Nouvelle configuration non validée ; profil précédent réactivé.' >&2
    elif command -v ifquery >/dev/null && ifquery --state "$interface" >/dev/null 2>&1; then
        confirmation=interactive
        if (( install_mode )); then confirmation=auto; fi
        if bash deploy/network-ifupdown.sh "$interface" "$mode" "$address" "$gateway" "$dns" "$confirmation"; then exit 0; fi
    else
        echo 'Interface non gérée par NetworkManager ni par un profil ifupdown actif. Aucune configuration modifiée.' >&2
        echo 'Configurer cette interface dans Debian, puis relancer deploy/network.sh --check.' >&2
        exit 1
    fi
    if (( install_mode )); then exit 1; fi
    sb_ask 'Réessayer la configuration ?' || exit 1
done
