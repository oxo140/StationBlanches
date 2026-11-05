#!/bin/bash
# Diagnostic sans mutation, utilisable avant apt et sans NetworkManager.
sb_default_interface() {
    ip -4 route show default | awk 'NR==1 {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1);exit}}'
}

sb_cidr4() {
    local value=$1 prefix=${1##*/}
    [[ "$value" == */* && "$prefix" =~ ^([1-9]|[12][0-9]|3[0-2])$ ]] || return 1
    sb_ipv4 "${value%/*}"
}

sb_dns4() {
    local value=$1 address
    local -a addresses
    read -r -a addresses <<< "$value"
    (( ${#addresses[@]} >= 1 && ${#addresses[@]} <= 3 )) || return 1
    for address in "${addresses[@]}"; do sb_ipv4 "$address" || return 1; done
}

sb_network_check() {
    local domain code failed=0 https_checked=0
    echo '=== Diagnostic réseau IPv4 ==='
    if command -v ip >/dev/null; then
        ip -br -4 address show
        if [[ -z $(ip -4 route show default) ]]; then
            echo '[ÉCHEC ROUTE] Aucune route IPv4 par défaut : vérifier DHCP, passerelle et carte réseau de la VM.' >&2
            failed=1
        else
            ip -4 route show default
        fi
    else
        echo '[INFO] iproute2 absent : affichage des interfaces indisponible.'
    fi
    if command -v ping >/dev/null; then
        if ping -4 -n -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
            echo '[OK] Ping IPv4 vers 8.8.8.8 (Google DNS).'
        else
            echo '[INFO] Ping 8.8.8.8 sans réponse ; ICMP peut être filtré. Le DNS et HTTPS restent les critères de connexion.'
        fi
    else
        echo '[INFO] ping absent ; le diagnostic continue avec DNS et HTTPS.'
    fi
    for domain in google.com download.docker.com deb.debian.org github.com raw.githubusercontent.com registry-1.docker.io auth.docker.io database.clamav.net; do
        if timeout 5 getent ahostsv4 "$domain" >/dev/null 2>&1; then
            echo "[OK DNS] $domain"
        else
            if [[ "$domain" == google.com ]]; then
                echo '[INFO] google.com non résolu ; les domaines nécessaires à la station restent les critères de validation.'
            else
                echo "[ÉCHEC DNS] $domain : nom impossible à résoudre. Vérifier les DNS fournis par DHCP ou choisir des DNS manuels." >&2
                failed=1
            fi
        fi
    done
    if command -v ping >/dev/null && timeout 5 getent ahostsv4 google.com >/dev/null 2>&1; then
        if ping -4 -n -c 1 -W 2 google.com >/dev/null 2>&1; then
            echo '[OK] Ping google.com.'
        else
            echo '[INFO] Ping google.com filtré ou sans réponse.'
        fi
    fi
    if ! command -v curl >/dev/null; then
        echo '[INFO] curl absent : contrôle HTTPS différé après installation du paquet.'
    else
        https_checked=1
        for domain in https://download.docker.com/linux/debian/gpg https://deb.debian.org/debian/; do
            if curl -4 --fail --silent --show-error --location --head --connect-timeout 5 --max-time 12 "$domain" >/dev/null; then
                echo "[OK HTTPS] $domain"
            else
                code=$?
                sb_curl_error "$code" "$domain"
                failed=1
            fi
        done
    fi
    if (( failed )); then
        echo '[ARRÊT] Réseau non prêt : aucune tentative de téléchargement Docker ne sera poursuivie.' >&2
        return 1
    fi
    if (( https_checked )); then
        echo '[OK] Connectivité IPv4, résolution DNS et contrôles HTTPS disponibles.'
    else
        echo '[OK] Résolution DNS disponible ; contrôle HTTPS à refaire après installation de curl.'
    fi
}

sb_curl_error() {
    case "$1" in
        6) echo "[ERREUR DNS / curl 6] Impossible de résoudre $2. L'adresse DHCP ne suffit pas si le DNS est défaillant." >&2 ;;
        5) echo '[ERREUR PROXY] Impossible de résoudre le proxy configuré.' >&2 ;;
        7|28) echo "[ERREUR RÉSEAU / curl $1] Connexion impossible ou délai dépassé vers $2 : vérifier route, pare-feu et proxy." >&2 ;;
        35|60|77) echo "[ERREUR TLS / curl $1] Vérifier l'heure de Debian et les certificats CA. La vérification TLS reste activée." >&2 ;;
        *) echo "[ERREUR curl $1] Téléchargement impossible : $2" >&2 ;;
    esac
}

sb_fetch() {
    local code
    if curl -4 --fail --silent --show-error --location --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 2 "$1" -o "$2"; then return 0; else code=$?; fi
    sb_curl_error "$code" "$1"
    echo 'Relancer le diagnostic : sudo bash deploy/network.sh --check ; configuration : sudo bash deploy/network.sh' >&2
    return "$code"
}

# Réécrit uniquement les options IPv4 de la stanza sélectionnée ; les autres interfaces et IPv6 sont conservés.
sb_render_interfaces() {
    local file=$1 iface=$2 mode=$3 address=$4 gateway=$5 dns=$6
    awk -v iface="$iface" -v mode="$mode" -v address="$address" -v gateway="$gateway" -v dns="$dns" '
        $1=="iface" || $1=="auto" || $1~/^allow-/ || $1=="mapping" || $1=="source" || $1=="source-directory" || $1=="rename" { selected=0 }
        $1=="iface" && $2==iface && $3=="inet" {
            selected=1
            if(mode=="dns") print $0; else print "iface " iface " inet " (mode=="manual" ? "static" : "dhcp")
            if(mode=="manual") {print "    address " address;print "    gateway " gateway}
            if(dns!="") print "    dns-nameservers " dns
            next
        }
        selected && $1=="dns-nameservers" {next}
        selected && mode!="dns" && $1~/^(address|netmask|gateway|broadcast|network)$/ {next}
        {print}
    ' "$file"
}

sb_remove_dns_block() {
    awk -v begin="# BEGIN station-blanche $2" -v end="# END station-blanche $2" '
        $0==begin {skip=1;next} $0==end {skip=0;next} !skip {print}
    ' "$1"
}
