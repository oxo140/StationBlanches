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

# === Répertoire d'images ===
echo "[INFO] Vérification/Création du répertoire d'images..."
sudo mkdir -p "$IMAGES_DIR"

# === Téléchargement des images UI ===
echo "[INFO] Téléchargement des images..."
wget -O "$IMAGES_DIR/no_usb.png"     "$IMAGE_REPO/no_usb.png"
wget -O "$IMAGES_DIR/scanning.png"   "$IMAGE_REPO/scanning.png"
wget -O "$IMAGES_DIR/infected.png"   "$IMAGE_REPO/infected.png"
wget -O "$IMAGES_DIR/clean.png"      "$IMAGE_REPO/clean.png"
wget -O "$IMAGES_DIR/perte.png"      "$IMAGE_REPO/perte.png"

# === Répertoire de quarantaine ===
echo "[INFO] Vérification du répertoire de quarantaine..."
if [ ! -d "/quarantaine" ]; then
  sudo mkdir /quarantaine
  sudo chown clamav:clamav /quarantaine
fi

# === Récupération des scripts applicatifs ===
echo "[INFO] Téléchargement des scripts principaux..."
(cd "$INSTALL_DIR" && \
  curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/script.py && \
  curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/script_monitor.sh && \
  curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/usb_monitor.py)
chmod +x "$INSTALL_DIR/script_monitor.sh"

# === Hash DB MalwareBazaar : script d'update + initial fetch ===
echo "[INFO] Préparation de la base hash (init + update automatique)..."
mkdir -p "$HASH_DIR"

cat > "$INSTALL_DIR/update_hashdb.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="__INSTALL_DIR__"
HASH_DIR="$SCRIPT_DIR/hashdb"
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

# Injecte le chemin d'installation réel dans le script\lsed -i "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$INSTALL_DIR/update_hashdb.sh"
chmod +x "$INSTALL_DIR/update_hashdb.sh"

# Fetch initial
"$INSTALL_DIR/update_hashdb.sh" || echo "[WARN] Échec de l'init de la base hash (continuation)."

# === Cron pour freshclam & shutdown (inchangés) ===
echo "[INFO] Configuration de la mise à jour automatique de ClamAV tous les jours à 21h00..."
(crontab -l 2>/dev/null; echo "00 21 * * * sudo freshclam") | crontab -

echo "[INFO] Configuration de l'arrêt automatique à 22h00..."
(crontab -l 2>/dev/null; echo "00 22 * * * sudo shutdown -h now") | crontab -

# === DISPLAY pour éventuellement lancer une UI en TTY ===
echo "[INFO] Vérification et ajout de 'export DISPLAY=:0' dans ~/.bashrc..."
if ! grep -q "export DISPLAY=:0" ~/.bashrc; then
  echo "export DISPLAY=:0" >> ~/.bashrc
  echo "[INFO] Ajouté."
else
  echo "[INFO] Déjà présent."
fi

# Appliquer immédiatement (dans ce shell)
source ~/.bashrc || true

# === Nom d'utilisateur ciblé pour les services ===
ACTIVE_USER=$(who | awk '{print $1}' | head -n 1)
echo "Nom d'utilisateur détecté : $ACTIVE_USER"
read -p "Entrez le nom d'utilisateur pour les services systemd ($ACTIVE_USER) : " USERNAME
USERNAME=${USERNAME:-$ACTIVE_USER}
echo "[INFO] Nom d'utilisateur sélectionné : $USERNAME"

# === Services systemd (script_monitor, usb_monitor) ===
echo "[INFO] Création du service systemd pour script_monitor.sh..."
cat << EOF2 | sudo tee /etc/systemd/system/script_monitor.service >/dev/null
[Unit]
Description=Surveillance de l'exécution du script Python
After=network.target

[Service]
ExecStart=$INSTALL_DIR/script_monitor.sh
Restart=always
User=$USERNAME
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF2


echo "[INFO] Création du service systemd pour usb_monitor.py..."
cat << EOF3 | sudo tee /etc/systemd/system/usb_monitor.service >/dev/null
[Unit]
Description=Surveillance des périphériques USB
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/usb_monitor.py
Restart=always
User=$USERNAME
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF3

# === Service + Timer systemd pour la mise à jour quotidienne de la hash DB ===
echo "[INFO] Création du service + timer pour update_hashdb (quotidien, 10h & 18h)..."
cat << EOF4 | sudo tee /etc/systemd/system/update_hashdb.service >/dev/null
[Unit]
Description=Met à jour la base de hash (MalwareBazaar)

[Service]
Type=oneshot
User=$USERNAME
ExecStart=$INSTALL_DIR/update_hashdb.sh
WorkingDirectory=$INSTALL_DIR
EOF4

cat << 'EOF5' | sudo tee /etc/systemd/system/update_hashdb.timer >/dev/null
[Unit]
Description=Lance update_hashdb deux fois par jour (10:00, 18:00)

[Timer]
OnCalendar=*-*-* 10:00:00
OnCalendar=*-*-* 18:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF5

# === Activation des services/timers ===
echo "[INFO] Activation et démarrage des services systemd..."
sudo systemctl daemon-reload
sudo systemctl enable --now script_monitor.service
sudo systemctl enable --now usb_monitor.service

sudo systemctl enable --now update_hashdb.timer

# === Optionnel : installation système d'envoi de mails ===
read -p "[INFO] Souhaitez-vous mettre en place l'envoi d'e-mails en cas d'infection détectée ? (oui/non) : " INSTALL_MAIL
if [[ "${INSTALL_MAIL:-non}" == "oui" ]]; then
  echo "[INFO] Téléchargement et exécution de mailinstall.sh..."
  (cd "$INSTALL_DIR" && curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/mailinstall.sh)
  chmod +x "$INSTALL_DIR/mailinstall.sh"
  "$INSTALL_DIR/mailinstall.sh"
else
  echo "[INFO] Envoi d'e-mails non configuré."
fi

# === Fin ===
echo "[INFO] Installation terminée avec succès."
echo "[INFO] Pensez à désactiver la mise en veille de l'ordinateur et à activer l'ouverture automatique de session."
echo "[INFO] Vérifier le timer : 'sudo systemctl status update_hashdb.timer' et voir les prochaines exécutions avec 'systemctl list-timers | grep update_hashdb'"
