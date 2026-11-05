#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ $EUID == 0 ]] || { echo 'Utiliser sudo bash deploy/desktop.sh [UTILISATEUR].' >&2; exit 1; }
# shellcheck source=deploy/lib.sh
source deploy/lib.sh
# shellcheck source=deploy/apt-lib.sh
source deploy/apt-lib.sh
desktop_user=$(sb_desktop_user "${1:-}" || true)
[[ -n "$desktop_user" && "$desktop_user" != root ]] || { echo 'Préciser le compte bureau non root.' >&2; exit 1; }
sb_apt_install_missing python3 x11-xserver-utils
install -d -m 0755 /usr/local/lib/station-blanche
install -m 0755 deploy/host/kiosk-launch.sh deploy/host/desktop-config.py deploy/host/desktop-session.py deploy/host/kiosk-supervisor.py /usr/local/lib/station-blanche/
install -d -m 0755 /etc/station-blanche
station_ip=$(sed -n 's/^STATION_IP=//p' .env)
sb_ipv4 "$station_ip" || { echo 'Adresse IPv4 absente ou invalide dans .env.' >&2; exit 1; }
printf 'https://%s\n' "$station_ip" > /etc/station-blanche/kiosk-origin
python3 /usr/local/lib/station-blanche/desktop-config.py "$desktop_user"
user_home=$(getent passwd "$desktop_user" | cut -d: -f6)
desktop_group=$(id -gn "$desktop_user")
runuser -u "$desktop_user" -- mkdir -p "$user_home/.config/autostart"
cat > "$user_home/.config/autostart/station-blanche.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Station Blanche
Exec=/usr/local/lib/station-blanche/kiosk-launch.sh
Terminal=false
X-GNOME-Autostart-enabled=true
EOF
chown "$desktop_user:$desktop_group" "$user_home/.config/autostart/station-blanche.desktop"
chmod 0644 "$user_home/.config/autostart/station-blanche.desktop"
