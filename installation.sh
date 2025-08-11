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
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget curl python3-pyudev xdotool unzip unclutter
sudo apt install python3-selenium
sudo apt install -y python3-psutil

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

# 7) Configuration interactive
echo "[INFO] Configuration interactive..."

# Demande du nom d'utilisateur pour l'autologin
read -p "Nom d'utilisateur pour l'autologin au démarrage [défaut: sbblanche] : " AUTOLOGIN_USER
AUTOLOGIN_USER=${AUTOLOGIN_USER:-sbblanche}

# Demande de l'heure d'extinction
read -p "À quelle heure voulez-vous éteindre le PC automatiquement ? (format HH, ex: 22 pour 22h00) [défaut: 22] : " SHUTDOWN_HOUR
SHUTDOWN_HOUR=${SHUTDOWN_HOUR:-22}

# Validation de l'heure
if ! [[ "$SHUTDOWN_HOUR" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
    echo "[ERREUR] Heure invalide. Utilisation de 22h par défaut."
    SHUTDOWN_HOUR=22
fi

echo "[INFO] PC configuré pour s'éteindre à ${SHUTDOWN_HOUR}h00"

# Demande de configuration email
read -p "Voulez-vous configurer l'envoi d'emails pour les alertes ? (o/n) [défaut: n] : " CONFIG_EMAIL
CONFIG_EMAIL=${CONFIG_EMAIL:-n}

if [[ "$CONFIG_EMAIL" =~ ^[oO]$ ]]; then
    echo "[INFO] Téléchargement du script d'installation mail..."
    curl -o "$SCRIPT_DIR/mailinstall.sh" "https://raw.githubusercontent.com/oxo140/StationBlanches/main/mailinstall.sh"
    chmod +x "$SCRIPT_DIR/mailinstall.sh"
    echo "[INFO] Lancement de l'installation et configuration email..."
    echo "=========================================="
    cd "$SCRIPT_DIR"
    ./mailinstall.sh
    echo "=========================================="
    echo "[INFO] Configuration email terminée."
fi

# Configuration de l'autologin
echo "[INFO] Configuration de l'autologin pour l'utilisateur: $AUTOLOGIN_USER"

# Sauvegarde du fichier lightdm.conf original
sudo cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup 2>/dev/null || true

# Décommenter ou ajouter les lignes d'autologin dans la section [Seat:*]
sudo sed -i '/^\[Seat:\*\]/,/^\[/ {
    s/^#autologin-user=.*/autologin-user='$AUTOLOGIN_USER'/
    s/^#autologin-user-timeout=.*/autologin-user-timeout=0/
}' /etc/lightdm/lightdm.conf

# Si les lignes n'existent pas, les ajouter après [Seat:*]
if ! sudo grep -q "^autologin-user=" /etc/lightdm/lightdm.conf; then
    sudo sed -i '/^\[Seat:\*\]/a autologin-user='$AUTOLOGIN_USER'' /etc/lightdm/lightdm.conf
fi
if ! sudo grep -q "^autologin-user-timeout=" /etc/lightdm/lightdm.conf; then
    sudo sed -i '/^autologin-user=/a autologin-user-timeout=0' /etc/lightdm/lightdm.conf
fi

echo "[INFO] Autologin configuré pour l'utilisateur: $AUTOLOGIN_USER"

# Ajout du script au démarrage automatique XFCE
echo "[INFO] Configuration du démarrage automatique XFCE..."
sudo -u $AUTOLOGIN_USER mkdir -p /home/$AUTOLOGIN_USER/.config/autostart

sudo -u $AUTOLOGIN_USER bash -c "cat > /home/$AUTOLOGIN_USER/.config/autostart/station_blanche.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Station Blanche Auto
Comment=Lancement automatique Station Blanche
Exec=/home/sbblanche/check_and_start_script.sh
Icon=applications-development
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
Terminal=false
EOF"

# Ajout également dans le profil bash pour double sécurité
echo "[INFO] Ajout du lancement au profil utilisateur..."
if ! grep -q "check_and_start_script.sh" /home/$AUTOLOGIN_USER/.bashrc 2>/dev/null; then
    sudo -u $AUTOLOGIN_USER bash -c "echo '# Auto-start Station Blanche' >> /home/$AUTOLOGIN_USER/.bashrc"
    sudo -u $AUTOLOGIN_USER bash -c "echo 'if [ \"\$DISPLAY\" ] && [ -z \"\$SSH_CLIENT\" ]; then' >> /home/$AUTOLOGIN_USER/.bashrc"
    sudo -u $AUTOLOGIN_USER bash -c "echo '    /home/sbblanche/check_and_start_script.sh &' >> /home/$AUTOLOGIN_USER/.bashrc"
    sudo -u $AUTOLOGIN_USER bash -c "echo 'fi' >> /home/$AUTOLOGIN_USER/.bashrc"
fi

echo "[INFO] Démarrage automatique configuré via XFCE autostart et .bashrc"

# 8) Script de vérification et lancement automatique
echo "[INFO] Création du script de vérification et auto-start..."
cat > "$SCRIPT_DIR/check_and_start_script.sh" << 'EOF'
#!/bin/bash
# Vérifie si le script est déjà en cours d'exécution
if ! pgrep -f "python3.*script.py gui" > /dev/null; then
    cd /home/sbblanche
    export DISPLAY=:0
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    # Cache le curseur de la souris
    unclutter -idle 1 -root &
    /usr/bin/python3 script.py gui &
    sleep 8
    xdotool key Escape 2>/dev/null || true
fi
EOF
chmod +x "$SCRIPT_DIR/check_and_start_script.sh"

# 8) Crontab : vérification toutes les minutes + mise à jour base hash + maintenance
echo "[INFO] Configuration du crontab..."
# Supprime les anciennes entrées si elles existent
crontab -l 2>/dev/null | grep -v "check_and_start_script.sh" | grep -v "full.zip" | grep -v "freshclam" | grep -v "shutdown" | crontab - 2>/dev/null || true

# Ajoute les nouvelles entrées
(crontab -l 2>/dev/null; echo "# Auto-start du script GUI toutes les minutes") | crontab -
(crontab -l 2>/dev/null; echo "* * * * * $SCRIPT_DIR/check_and_start_script.sh") | crontab -
(crontab -l 2>/dev/null; echo "# Mise à jour base hash à 10h et 18h") | crontab -
(crontab -l 2>/dev/null; echo "0 10,18 * * * $SCRIPT_DIR/update_hashdb.sh") | crontab -
(crontab -l 2>/dev/null; echo "# Mise à jour ClamAV à 21h") | crontab -
(crontab -l 2>/dev/null; echo "0 21 * * * sudo freshclam") | crontab -
(crontab -l 2>/dev/null; echo "# Arrêt automatique à ${SHUTDOWN_HOUR}h") | crontab -
(crontab -l 2>/dev/null; echo "0 $SHUTDOWN_HOUR * * * sudo shutdown -h now") | crontab -

# 9) Script de lancement GUI avec ESC auto (gardé comme backup)
echo "[INFO] Création du script de lancement GUI avec ESC auto..."
cat > "$SCRIPT_DIR/launch_station.sh" << 'EOF'
#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
# Cache le curseur de la souris
unclutter -idle 1 -root &
/usr/bin/python3 /home/sbblanche/script.py gui &
sleep 8
xdotool key Escape
wait
EOF
chmod +x "$SCRIPT_DIR/launch_station.sh"

# 10) Service systemd utilisateur (gardé comme backup)
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

# On désactive le service systemd car on utilise maintenant le crontab
sudo -u sbblanche XDG_RUNTIME_DIR=/run/user/$(id -u sbblanche) systemctl --user daemon-reload
sudo -u sbblanche XDG_RUNTIME_DIR=/run/user/$(id -u sbblanche) systemctl --user disable station_blanche.service 2>/dev/null || true
sudo -u sbblanche XDG_RUNTIME_DIR=/run/user/$(id -u sbblanche) systemctl --user stop station_blanche.service 2>/dev/null || true

# 11) Permissions et finalisation
chmod 777 "$SCRIPT_DIR/station_blanche_hash.log" 2>/dev/null || true

echo "✅ Installation terminée."
echo "[INFO] Autologin configuré pour: $AUTOLOGIN_USER"
echo "[INFO] Le script se lancera automatiquement toutes les minutes via crontab."
echo "[INFO] PC configuré pour s'éteindre à ${SHUTDOWN_HOUR}h00"
echo "[INFO] Curseur de souris automatiquement caché"
echo "[INFO] Pour vérifier le crontab : crontab -l"
echo "[INFO] Pour voir les processus : pgrep -f 'python3.*script.py gui'"
echo "[INFO] Logs mise à jour hash : tail -f $SCRIPT_DIR/hashdb_update.log"

# Demande de redémarrage
read -p "Voulez-vous redémarrer maintenant pour finaliser l'installation ? (o/N) " reponse
# Normaliser en minuscule
reponse=$(echo "$reponse" | tr '[:upper:]' '[:lower:]')
if [[ "$reponse" == "o" || "$reponse" == "oui" ]]; then
    echo "🔄 Redémarrage en cours..."
    sudo reboot
else
    echo "⏳ Redémarrage annulé. Pensez à redémarrer plus tard pour appliquer les changements."
fi
