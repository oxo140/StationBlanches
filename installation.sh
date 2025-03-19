#!/bin/bash

# Récupérer le chemin du script d'installation
SCRIPT_PATH="$(pwd)/script.py"

# Variables pour le dépôt d'images
IMAGE_REPO="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
IMAGES_DIR="/SB-Blanc"

# Mise à jour des dépôts et des paquets
echo "[INFO] Mise à jour des dépôts et des paquets..."
sudo apt update && sudo apt upgrade -y

# Installer les dépendances nécessaires
echo "[INFO] Installation des dépendances..."
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget curl python3-pyudev

# Activer et démarrer le service clamav-freshclam
echo "[INFO] Activation et démarrage de clamav-freshclam..."
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

# Mise à jour de la base de données ClamAV
echo "[INFO] Mise à jour de la base de données ClamAV..."
sudo freshclam

# Création du répertoire d'images si inexistant
echo "[INFO] Vérification du répertoire d'images..."
if [ ! -d "$IMAGES_DIR" ]; then
    sudo mkdir "$IMAGES_DIR"
fi

# Téléchargement des images depuis le dépôt GitHub
echo "[INFO] Téléchargement des images..."
wget -O "$IMAGES_DIR/no_usb.png" "$IMAGE_REPO/no_usb.png"
wget -O "$IMAGES_DIR/scanning.png" "$IMAGE_REPO/scanning.png"
wget -O "$IMAGES_DIR/infected.png" "$IMAGE_REPO/infected.png"
wget -O "$IMAGES_DIR/clean.png" "$IMAGE_REPO/clean.png"
wget -O "$IMAGES_DIR/perte.png" "$IMAGE_REPO/perte.png"

# Création du répertoire de quarantaine si inexistant
echo "[INFO] Vérification du répertoire de quarantaine..."
if [ ! -d "/quarantaine" ]; then
    sudo mkdir /quarantaine
    sudo chown clamav:clamav /quarantaine
fi

# Télécharger le script Python depuis GitHub
echo "[INFO] Téléchargement du script Python..."
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/script.py

# Télécharger le script de surveillance depuis GitHub
echo "[INFO] Téléchargement du script de surveillance..."
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/script_monitor.sh
chmod +x ./script_monitor.sh

# Télécharger le script USB monitor depuis GitHub (usb_monitor.py)
echo "[INFO] Téléchargement du script USB monitor..."
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/usb_monitor.py

# Mise à jour automatique de ClamAV à 21h00 tous les jours
echo "[INFO] Configuration de la mise à jour automatique de ClamAV tous les jours à 21h00..."
(crontab -l ; echo "00 21 * * * sudo freshclam") | crontab -

# Configuration de l'arrêt automatique
echo "[INFO] Configuration de l'arrêt automatique de l'ordinateur à 22h00..."
(crontab -l ; echo "00 22 * * * sudo shutdown -h now") | crontab -

# Ajout de la ligne DISPLAY=:0 dans ~/.bashrc si elle n'existe pas
echo "[INFO] Vérification et ajout de la ligne 'export DISPLAY=:0' dans ~/.bashrc..."
if ! grep -q "export DISPLAY=:0" ~/.bashrc; then
  echo "export DISPLAY=:0" >> ~/.bashrc
  echo "La ligne 'export DISPLAY=:0' a été ajoutée à ~/.bashrc."
else
  echo "La ligne 'export DISPLAY=:0' est déjà présente dans ~/.bashrc."
fi

# Appliquer immédiatement les changements de ~/.bashrc
source ~/.bashrc

# Demander à l'utilisateur l'utilisateur pour le service systemd
echo "[INFO] Pensez à désactiver la mise en veille de l'ordinateur et à activer l'ouverture automatique de session."

# Récupérer le nom d'utilisateur actif
ACTIVE_USER=$(who | awk '{print $1}' | head -n 1)

# Demander confirmation ou modification du nom d'utilisateur
echo "Nom d'utilisateur détecté : $ACTIVE_USER"
read -p "Entrez le nom d'utilisateur pour le service systemd ($ACTIVE_USER) : " USERNAME

# Utiliser le nom détecté par défaut si l'utilisateur n'entre rien
USERNAME=${USERNAME:-$ACTIVE_USER}

echo "Nom d'utilisateur sélectionné : $USERNAME"

# Création du service systemd pour script_monitor.sh
echo "[INFO] Création du service systemd pour monitor.sh..."

cat << EOF | sudo tee /etc/systemd/system/script_monitor.service
[Unit]
Description=Surveillance de l'exécution du script Python
After=network.target

[Service]
ExecStart=$(pwd)/script_monitor.sh
Restart=always
User=$USERNAME
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF

# Création du service systemd pour usb_monitor.py
echo "[INFO] Création du service systemd pour usb_monitor.py..."

cat << EOF | sudo tee /etc/systemd/system/usb_monitor.service
[Unit]
Description=Surveillance des périphériques USB
After=network.target

[Service]
ExecStart=/usr/bin/python3 $(pwd)/usb_monitor.py
Restart=always
User=$USERNAME
WorkingDirectory=$(pwd)

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer les services systemd
echo "[INFO] Activation et démarrage des services systemd..."
sudo systemctl daemon-reload
sudo systemctl enable script_monitor.service
sudo systemctl start script_monitor.service

sudo systemctl enable usb_monitor.service
sudo systemctl start usb_monitor.service

echo "[INFO] Les services systemd sont maintenant actifs. Les scripts seront surveillés et relancés automatiquement si nécessaire."

# Attente clavier pour redémarrage
echo "[INFO] Installation terminée avec succès."
echo "[INFO] Pensez à désactiver la mise en veille de l'ordinateur et à activer l'ouverture automatique de session."
