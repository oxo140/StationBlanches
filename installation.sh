#!/bin/bash

# Récupérer le chemin du script d'installation
SCRIPT_PATH="$(pwd)/script.py"  # Le chemin du script d'installation actuel

# Variables pour le dépôt d'images
IMAGE_REPO="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
IMAGES_DIR="/SB-Blanc"

# Mise à jour des dépôts et des paquets
echo "[INFO] Mise à jour des dépôts et des paquets..."
sudo apt update && sudo apt upgrade -y

# Installer les dépendances nécessaires
echo "[INFO] Installation des dépendances..."
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget curl

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
wget -O "$IMAGES_DIR/perte.png" "$IMAGE_REPO/perte.png"  # Nouvelle image

# Création du répertoire de quarantaine si inexistant
echo "[INFO] Vérification du répertoire de quarantaine..."
if [ ! -d "/quarantaine" ]; then
    sudo mkdir /quarantaine
    sudo chown clamav:clamav /quarantaine
fi

# Télécharger le script Python depuis GitHub
echo "[INFO] Téléchargement du script Python..."
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/script.py

# Mise à jour automatique de ClamAV à 13h30 tous les jours
echo "[INFO] Configuration de la mise à jour automatique de ClamAV tous les jours à 13h30..."
# Ajouter une entrée crontab pour la mise à jour de ClamAV
(crontab -l ; echo "30 13 * * * sudo freshclam") | crontab -


# Création du programme de surveillance pour garantir que le script Python reste en cours d'exécution
echo "[INFO] Création du programme de surveillance pour garantir que le script Python reste en cours d'exécution..."

# Créer un script de surveillance
cat << 'EOF' > /home/$USER/script_monitor.sh
#!/bin/bash
# Vérifier toutes les 5 secondes si le script Python est en cours d'exécution
SCRIPT_PATH="/home/$USER/script.py"
while true; do
    if ! pgrep -f "$SCRIPT_PATH" > /dev/null; then
        echo "[INFO] Le script $SCRIPT_PATH n'est pas en cours d'exécution. Lancement..."
        python3 "$SCRIPT_PATH" &
    else
        echo "[INFO] Le script $SCRIPT_PATH est déjà en cours d'exécution."
    fi
    sleep 5
done
EOF

# Rendre le script de surveillance exécutable
chmod +x /home/$USER/script_monitor.sh

# Créer un service systemd pour exécuter le script de surveillance en permanence
echo "[INFO] Création du service systemd pour monitor.sh..."

# Créer le fichier de service systemd
cat << EOF | sudo tee /etc/systemd/system/script_monitor.service
[Unit]
Description=Surveillance de l'exécution du script Python
After=multi-user.target

[Service]
ExecStart=/home/$USER/script_monitor.sh
Restart=always
User=$USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$USER/.Xauthority

[Install]
WantedBy=multi-user.target
EOF

# Activer et démarrer le service systemd
echo "[INFO] Activation et démarrage du service systemd..."
sudo systemctl daemon-reload
sudo systemctl enable script_monitor.service
sudo systemctl start script_monitor.service

echo "[INFO] Le service systemd est maintenant actif. Le script Python sera surveillé et relancé automatiquement si nécessaire."

echo "[INFO] Installation terminée avec succès."
echo "[INFO] Pensez à désactiver la mise en veille de l'ordinateur et à activer l'ouverture automatique de session."
