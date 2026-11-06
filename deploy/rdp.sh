#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $EUID == 0 ]] || { echo 'Utiliser sudo bash deploy/rdp.sh [UTILISATEUR].' >&2; exit 1; }
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
desktop_user=$(sb_desktop_user "${1:-}" || true)
[[ -n "$desktop_user" && "$desktop_user" != root ]] || { echo 'Préciser un compte Debian non root.' >&2; exit 1; }
station_ip=$(sed -n 's/^STATION_IP=//p' .env)
sb_ipv4 "$station_ip" || { echo 'STATION_IP invalide dans .env.' >&2; exit 1; }
sb_apt_install_missing xrdp xorgxrdp xfce4 xfce4-terminal dbus-x11 python3 ssl-cert openssl
getent group station-rdp >/dev/null || groupadd --system station-rdp
usermod -a -G station-rdp "$desktop_user"
usermod -a -G ssl-cert xrdp
install -d -m 0755 /usr/local/lib/station-blanche
install -m 0755 deploy/host/rdp-config.py deploy/host/rdp-session.sh deploy/host/desktop-config.py /usr/local/lib/station-blanche/
python3 /usr/local/lib/station-blanche/rdp-config.py "$station_ip"
install -d -m 0755 /etc/systemd/system/xrdp.service.d
cat > /etc/systemd/system/xrdp.service.d/station-blanche.conf <<'EOF'
[Unit]
Wants=network-online.target
After=network-online.target
[Service]
Restart=on-failure
RestartSec=5
EOF
# Préserver le pare-feu existant ; si UFW est actif, autoriser seulement le sous-réseau local.
if command -v ufw >/dev/null && LC_ALL=C ufw status | grep -q '^Status: active'; then
    subnet=$(ip -j -4 address show | python3 -c 'import ipaddress,json,sys; ip=sys.argv[1]; print(next(str(ipaddress.IPv4Interface(a["local"]+"/"+str(a["prefixlen"])).network) for dev in json.load(sys.stdin) for a in dev["addr_info"] if a.get("local")==ip))' "$station_ip")
    ufw allow from "$subnet" to "$station_ip" port 3389 proto tcp comment 'Station Blanche RDP LAN'
fi
systemctl daemon-reload
systemctl start xrdp-sesman
systemctl enable --now xrdp
if ss -Htn state established '( sport = :3389 )' | grep -q .; then
    echo '[RDP] Connexion distante active : services conservés. Les changements éventuels seront chargés au prochain redémarrage.'
else
    systemctl restart xrdp-sesman xrdp
fi
bash deploy/check-rdp.sh
echo "Accès Windows : mstsc /v:$station_ip:3389 — compte $desktop_user, mot de passe Debian existant."
