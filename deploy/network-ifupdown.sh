#!/bin/bash
# Les chaînes littérales génèrent des hooks shell dont les variables seront lues lors des baux DHCP.
# shellcheck disable=SC2016
set -Eeuo pipefail
umask 077
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/network-lib.sh
source deploy/network-lib.sh
[[ $EUID == 0 && $# == 5 ]] || exit 1
sb_require_tty
interface=$1; mode=$2; address=$3; gateway=$4; dns=$5
[[ "$interface" =~ ^[a-zA-Z0-9_.-]+$ && "$interface" != lo ]] || exit 1
[[ "$mode" == auto || "$mode" == manual || "$mode" == dns ]] || exit 1
if [[ "$mode" == manual ]]; then sb_cidr4 "$address"; sb_ipv4 "$gateway"; fi
if [[ -n "$dns" ]]; then sb_dns4 "$dns"; elif [[ "$mode" != auto ]]; then exit 1; fi
for required in ifup ifdown ifquery systemd-run systemctl; do command -v "$required" >/dev/null || exit 1; done
ifquery --state "$interface" >/dev/null
systemctl show-environment >/dev/null

# Ne pas interpréter des mappings / includes personnalisés ni écraser d'autres profils.
config=''; matches=0
for file in /etc/network/interfaces /etc/network/interfaces.d/*; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    count=$(awk -v iface="$interface" '$1=="iface" && $2==iface && $3=="inet" {n++} END{print n+0}' "$file")
    if (( count )); then config=$file; matches=$((matches+count)); fi
done
[[ $matches == 1 ]] || { echo 'Profil ifupdown complexe ou introuvable : configurer cette interface dans Debian, puis relancer le diagnostic.' >&2; exit 1; }
if grep -q '\\$' "$config"; then echo 'Profil avec continuation de ligne : modification automatique refusée.' >&2; exit 1; fi
[[ $(stat -c %u "$config") == 0 ]] || { echo 'Le profil réseau doit appartenir à root.' >&2; exit 1; }
if [[ -L /etc/resolv.conf ]] && ! command -v resolvconf >/dev/null && ! systemctl is-active --quiet systemd-resolved; then
    echo '/etc/resolv.conf est un lien géré par un résolveur non reconnu. Aucune modification ; utiliser son gestionnaire DNS.' >&2
    exit 1
fi
hook_up="/etc/network/if-up.d/zz-station-blanche-$interface"
hook_dhcp="/etc/dhcp/dhclient-enter-hooks.d/station-blanche-$interface"
for file in "$hook_up" "$hook_dhcp"; do
    if [[ -e "$file" ]] && ! grep -q '^# Station Blanche DNS$' "$file"; then echo "Hook préexistant non reconnu : $file" >&2; exit 1; fi
done
state_root=/var/lib/station-blanche-network
[[ ! -L "$state_root" ]] || exit 1
install -d -m 0700 "$state_root"
state=$(mktemp -d "$state_root/backup.XXXXXXXX")
unit="station-blanche-network-rollback-$(date +%s)-$RANDOM"
rollback="$state/rollback.sh"
printf '#!/bin/bash\nset -u\nsystemctl stop %q.timer 2>/dev/null || true\nifdown --force %q || true\n' "$unit" "$interface" > "$rollback"
index=0
for file in "$config" "$hook_up" "$hook_dhcp" /etc/dhcpcd.enter-hook; do
    [[ ! -L "$file" ]] || { echo "Lien symbolique non pris en charge : $file" >&2; exit 1; }
    if [[ -e "$file" ]]; then
        [[ -f "$file" ]] || exit 1
        cp -p -- "$file" "$state/file-$index"
        printf 'cp -p -- %q %q\n' "$state/file-$index" "$file" >> "$rollback"
    else
        printf 'rm -f -- %q\n' "$file" >> "$rollback"
    fi
    index=$((index+1))
done
if [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]]; then
    cp -p /etc/resolv.conf "$state/resolv.conf"
    # Restaurer les DNS avant et après la reprise du bail DHCP.
    printf 'cp -p -- %q /etc/resolv.conf\n' "$state/resolv.conf" >> "$rollback"
fi
printf 'if command -v resolvectl >/dev/null; then resolvectl revert %q || true; fi\ntimeout 45 ifup --force %q || true\n' "$interface" "$interface" >> "$rollback"
if [[ -f "$state/resolv.conf" ]]; then printf 'cp -p -- %q /etc/resolv.conf\n' "$state/resolv.conf" >> "$rollback"; fi
chmod 0700 "$rollback"
echo "Sauvegarde privée : $state ; restauration manuelle : sudo bash $rollback"
systemd-run --quiet --unit="$unit" --on-active=180s /bin/bash "$rollback"
deadline=$((SECONDS+170))
# Appelée par ERR ; le timer protège aussi une fermeture du terminal / une coupure SSH.
# shellcheck disable=SC2329
restore_on_error() {
    trap - ERR
    bash "$rollback"
    echo 'Configuration précédente restaurée.' >&2
    exit 1
}
trap restore_on_error ERR

temporary=$(mktemp "$(dirname "$config")/.station-blanche.XXXXXXXX")
sb_render_interfaces "$config" "$interface" "$mode" "$address" "$gateway" "$dns" > "$temporary"
chmod --reference="$config" "$temporary"
chown --reference="$config" "$temporary"
mv -f -- "$temporary" "$config"
install -d -m 0755 /etc/network/if-up.d /etc/dhcp/dhclient-enter-hooks.d
if [[ -n "$dns" ]]; then
    {
        printf '#!/bin/sh\n# Station Blanche DNS\n'
        printf 'if [ "${interface:-}" = "%s" ]; then\n    new_domain_name_servers="%s"\nfi\n' "$interface" "$dns"
    } > "$hook_dhcp"
    chmod 0644 "$hook_dhcp"
    {
        printf '#!/bin/sh\n# Station Blanche DNS\n[ "${IFACE:-}" = "%s" ] || exit 0\n' "$interface"
        printf 'if command -v resolvectl >/dev/null && systemctl is-active --quiet systemd-resolved; then\n'
        printf '    resolvectl dns "%s" %s\n    resolvectl domain "%s" "~."\n' "$interface" "$dns" "$interface"
        printf 'elif command -v resolvconf >/dev/null; then\n'
        printf "    printf '"
        for server in $dns; do printf 'nameserver %s\\n' "$server"; done
        printf "' | resolvconf -a '%s.inet'\n" "$interface"
        printf 'elif [ ! -L /etc/resolv.conf ]; then\n'
        printf "    printf '"
        for server in $dns; do printf 'nameserver %s\\n' "$server"; done
        printf "' > /etc/resolv.conf\nelse\n    exit 1\nfi\n"
    } > "$hook_up"
    chmod 0755 "$hook_up"
else
    rm -f -- "$hook_up" "$hook_dhcp"
fi
if [[ -f /etc/dhcpcd.enter-hook ]]; then
    sb_remove_dns_block /etc/dhcpcd.enter-hook "$interface" > "$state/dhcpcd-new"
else
    : > "$state/dhcpcd-new"
fi
if [[ -n "$dns" ]]; then
    {
        printf '\n# BEGIN station-blanche %s\n' "$interface"
        printf 'if [ "${interface:-}" = "%s" ]; then\n    new_domain_name_servers="%s"\nfi\n' "$interface" "$dns"
        printf '# END station-blanche %s\n' "$interface"
    } >> "$state/dhcpcd-new"
fi
if [[ -f /etc/dhcpcd.enter-hook ]]; then
    # Conserver les permissions de l'ancien hook, qui peut contenir des données privées.
    cat "$state/dhcpcd-new" > /etc/dhcpcd.enter-hook
else
    install -m 0644 "$state/dhcpcd-new" /etc/dhcpcd.enter-hook
fi
ifdown --force "$interface" || true
if timeout 45 ifup --force "$interface" && sb_network_check && sb_ask 'Conserver cette configuration (avant expiration du délai de 180 secondes) ?' N; then
    if (( SECONDS >= deadline )) || ! systemctl is-active --quiet "$unit.timer"; then restore_on_error; fi
    systemctl stop "$unit.timer"
    # Le timer doit encore être en attente : ne pas valider si une restauration a déjà démarré.
    if [[ $(systemctl show -p ExecMainStartTimestampMonotonic --value "$unit.service") != 0 ]]; then restore_on_error; fi
    trap - ERR
    echo '[OK] Configuration ifupdown et DNS persistants conservés.'
    exit 0
fi
restore_on_error
