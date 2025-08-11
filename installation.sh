#!/bin/bash
set -euo pipefail

# Installation et configuration complète de la Station Blanche avec ouverture auto de l'UI Tk et mise à jour hash DB

SCRIPT_DIR="/home/sbblanche"          # <- adapte si besoin
PY_CMD="/usr/bin/python3 $SCRIPT_DIR/script.py gui"
LOG_FILE="$SCRIPT_DIR/startup_gui.log"
IMAGE_REPO="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
IMAGES_DIR="/SB-Blanc"

# 1) Mise à jour système et installation des dépendances
echo "[INFO] Mise à jour du système et installation des dépendances..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget curl python3-pyudev xdotool unzip
sudo apt install python3-selenium
pip3 install psutil

# 2) Activation de ClamAV (correction freshclam init failed)
sudo systemctl stop clamav-freshclam
sudo freshclam
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

# 3) Création des répertoires
[ ! -d "$IMAGES_DIR" ] && sudo mkdir "$IMAGES_DIR"
[ ! -d "/quarantaine" ] && sudo mkdir /quarantaine && sudo chown clamav:clamav /quarantaine
[ ! -d "$SCRIPT_DIR/hashdb" ] && mkdir "$SCRIPT_DIR/hashdb"

# 4) Téléchargement images UI
wget -O "$IMAGES_DIR/no_usb.png" "$IMAGE_REPO/no_usb.png"
wget -O "$IMAGES_DIR/scanning.png" "$IMAGE_REPO/scanning.png"
wget -O "$IMAGES_DIR/infected.png" "$IMAGE_REPO/infected.png"
wget -O "$IMAGES_DIR/clean.png" "$IMAGE_REPO/clean.png"
wget -O "$IMAGES_DIR/perte.png" "$IMAGE_REPO/perte.png"

# 5) Téléchargement scripts
curl -o "$SCRIPT_DIR/script.py" "$IMAGE_REPO/script.py"
curl -o "$SCRIPT_DIR/script_monitor.sh" "$IMAGE_REPO/script_monitor.sh" && chmod +x "$SCRIPT_DIR/script_monitor.sh"
curl -o "$SCRIPT_DIR/usb_monitor.py" "$IMAGE_REPO/usb_monitor.py"

# 6) Téléchargement et extraction base hash
echo "[INFO] Téléchargement de la base hash..."
wget -O "$SCRIPT_DIR/full.zip" https://bazaar.abuse.ch/export/txt/sha256/full/
unzip -p "$SCRIPT_DIR/full.zip" > "$SCRIPT_DIR/hashdb/mb_full.txt"

# 7) Crontab : mise à jour base hash à 10h et 18h + freshclam à 21h + arrêt à 22h
(crontab -l 2>/dev/null; echo "0 10,18 * * * wget -O $SCRIPT_DIR/full.zip https://bazaar.abuse.ch/export/txt/sha256/full/ && unzip -p $SCRIPT_DIR/full.zip > $SCRIPT_DIR/hashdb/mb_full.txt") | crontab -
(crontab -l 2>/dev/null; echo "0 21 * * * sudo freshclam") | crontab -
(crontab -l 2>/dev/null; echo "0 22 * * * sudo shutdown -h now") | crontab -

# 8) Script de lancement GUI avec ESC auto
echo "[INFO] Création du script de lancement GUI avec ESC auto..."
cat > "$SCRIPT_DIR/launch_station.sh" << 'EOF'
#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
/usr/bin/python3 /home/sbblanche/script.py gui &
sleep 8
xdotool key Escape
wait
EOF
chmod +x "$SCRIPT_DIR/launch_station.sh"

# 9) Service systemd utilisateur
sudo loginctl enable-linger sbblanche
sudo -u sbblanche mkdir -p /home/sbblanche/.config/systemd/user
cat > /home/sbblanche/.config/systemd/user/station_blanche.service << EOF
[Unit]
Description=Station Blanche (GUI avec ESC auto)
After=graphical-session.target

[Service]
Type=simple
ExecStart=$SCRIPT_DIR/launch_station.sh
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

sudo -u sbblanche XDG_RUNTIME_DIR=/run/user/$(id -u sbblanche) systemctl --user daemon-reload
sudo -u sbblanche XDG_RUNTIME_DIR=/run/user/$(id -u sbblanche) systemctl --user enable --now station_blanche.service

echo "[INFO] Installation terminée. UI configurée pour se lancer au démarrage en plein écran avec ESC auto."
