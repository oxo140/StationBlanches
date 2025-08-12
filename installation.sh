#!/bin/bash
set -euo pipefail

# === Variables ===
INSTALL_DIR="$(pwd)"
SCRIPT_PATH="$INSTALL_DIR/script.py"
IMAGE_REPO="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
IMAGES_DIR="/SB-Blanc"
HASH_DIR="$INSTALL_DIR/hashdb"

# === MAJ système et dépendances ===
echo "[INFO] Mise à jour des dépôts et des paquets..."
sudo apt update && sudo apt upgrade -y

echo "[INFO] Installation des dépendances..."
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk \
  clamav wget curl python3-pyudev unzip python3-psutil

# === ClamAV (freshclam) ===
echo "[INFO] Activation et démarrage de clamav-freshclam..."
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

echo "[INFO] Première mise à jour de la base ClamAV..."
sudo freshclam || true

# === Répertoires et ressources ===
echo "[INFO] Préparation des répertoires..."
sudo mkdir -p "$IMAGES_DIR"
mkdir -p "$HASH_DIR"

if [ ! -d "/quarantaine" ]; then
  sudo mkdir /quarantaine
  sudo chown clamav:clamav /quarantaine
fi

# === Téléchargement des images UI ===
echo "[INFO] Téléchargement des images UI..."
wget -O "$IMAGES_DIR/no_usb.png"     "$IMAGE_REPO/no_usb.png"
wget -O "$IMAGES_DIR/scanning.png"   "$IMAGE_REPO/scanning.png"
wget -O "$IMAGES_DIR/infected.png"   "$IMAGE_REPO/infected.png"
wget -O "$IMAGES_DIR/clean.png"      "$IMAGE_REPO/clean.png"
wget -O "$IMAGES_DIR/perte.png"      "$IMAGE_REPO/perte.png"

# === Récupération des scripts applicatifs ===
echo "[INFO] Téléchargement des scripts applicatifs..."
(cd "$INSTALL_DIR" && \
  curl -O "$IMAGE_REPO/script.py" && \
  curl -O "$IMAGE_REPO/script_monitor.sh" && \
  curl -O "$IMAGE_REPO/usb_monitor.py")
chmod +x "$INSTALL_DIR/script_monitor.sh"

# === Hash DB MalwareBazaar : script d'update + initial fetch ===
echo "[INFO] Préparation de la base hash (init + update automatique)..."
cat > "$INSTALL_DIR/update_hashdb.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
HASH_DIR="__HASH_DIR__"
TMP_ZIP="$(mktemp --suffix=.zip)"
TMP_OUT="$(mktemp)"

mkdir -p "$HASH_DIR"

# Téléchargement silencieux ; échec si code != 0
wget -q -O "$TMP_ZIP" "https://bazaar.abuse.ch/export/txt/sha256/full/"

# Extraction en flux puis remplacement atomique
unzip -p "$TMP_ZIP" > "$TMP_OUT"
if [ -s "$TMP_OUT" ]; then
  mv "$TMP_OUT" "$HASH_DIR/mb_full.txt"
  echo "[INFO] Hash DB mise à jour : $(wc -l < "$HASH_DIR/mb_full.txt") lignes"
else
  echo "[WARN] Fichier vide, update ignorée."
  rm -f "$TMP_OUT"
fi
rm -f "$TMP_ZIP"
EOF
sed -i "s|__HASH_DIR__|$HASH_DIR|g" "$INSTALL_DIR/update_hashdb.sh"
chmod +x "$INSTALL_DIR/update_hashdb.sh"

# Fetch initial
"$INSTALL_DIR/update_hashdb.sh" || echo "[WARN] Échec de l'init de la base hash (continuation)."

# === Crons ClamAV & shutdown ===
echo "[INFO] Configuration de la mise à jour automatique de ClamAV (21:00) et arrêt (22:00)..."
(crontab -l 2>/dev/null; echo "0 21 * * * sudo freshclam") | crontab -
(crontab -l 2>/dev/null; echo "0 22 * * * sudo shutdown -h now") | crontab -

# === Nom utilisateur cible (services user GNOME) ===
ACTIVE_USER=$(who | awk '{print $1}' | head -n 1)
echo "Utilisateur détecté : $ACTIVE_USER"
read -p "Utilisateur pour services ($ACTIVE_USER) : " USERNAME
USERNAME=${USERNAME:-$ACTIVE_USER}
echo "[INFO] Utilisateur sélectionné : $USERNAME"
USER_UNIT_DIR="/home/$USERNAME/.config/systemd/user"
sudo -u "$USERNAME" mkdir -p "$USER_UNIT_DIR"

# === Services systemd UTILISATEUR (GNOME) ===
# GUI principale
cat > "$USER_UNIT_DIR/station_blanche.service" << EOF
[Unit]
Description=Station Blanche - UI Tk
After=graphical-session.target
Wants=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $INSTALL_DIR/script.py gui
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# Monitor
cat > "$USER_UNIT_DIR/script_monitor.service" << EOF
[Unit]
Description=Monitor Station Blanche
After=graphical-session.target
Wants=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/script_monitor.sh
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# USB monitor
cat > "$USER_UNIT_DIR/usb_monitor.service" << EOF
[Unit]
Description=USB Monitor Station Blanche
After=graphical-session.target
Wants=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $INSTALL_DIR/usb_monitor.py
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# Timer d'update hash (USER) — 10:00 et 18:00, persistant
cat > "$USER_UNIT_DIR/update_hashdb.service" << EOF
[Unit]
Description=MAJ Hash DB MalwareBazaar

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/update_hashdb.sh
WorkingDirectory=$INSTALL_DIR
EOF

cat > "$USER_UNIT_DIR/update_hashdb.timer" << EOF
[Unit]
Description=MAJ Hash DB 10h et 18h (user)

[Timer]
OnCalendar=*-*-* 10:00:00
OnCalendar=*-*-* 18:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Activer la persistance utilisateur (permet aux timers user de tourner sans session)
sudo loginctl enable-linger "$USERNAME" || true

# Activer et démarrer (user)
sudo -u "$USERNAME" XDG_RUNTIME_DIR=/run/user/$(id -u "$USERNAME") systemctl --user daemon-reload
sudo -u "$USERNAME" XDG_RUNTIME_DIR=/run/user/$(id -u "$USERNAME") systemctl --user enable --now \
  station_blanche.service script_monitor.service usb_monitor.service update_hashdb.timer

# === Fin ===
echo "[INFO] Installation terminée."
echo "[INFO] Vérifs :"
echo "- systemctl --user status station_blanche.service (en session $USERNAME)"
echo "- systemctl --user list-timers | grep update_hashdb"
echo "- journalctl --user -u station_blanche.service -n 100 --no-pager"
