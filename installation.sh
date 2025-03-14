#!/bin/bash

# Mettre à jour les dépôts et les paquets
sudo apt update && sudo apt upgrade -y

# Installer les dépendances nécessaires
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget

# Activer et démarrer le service clamav-freshclam
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

# Mise à jour de la base de données ClamAV
sudo freshclam

# Création du répertoire d'images si inexistant
if [ ! -d "/SB-Blanc" ]; then
    sudo mkdir /SB-Blanc
fi

# Téléchargement des images depuis le dépôt GitHub
IMAGES_URL="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
wget -O /SB-Blanc/no_usb.png "$IMAGES_URL/no_usb.png"
wget -O /SB-Blanc/scanning.png "$IMAGES_URL/scanning.png"
wget -O /SB-Blanc/infected.png "$IMAGES_URL/infected.png"
wget -O /SB-Blanc/clean.png "$IMAGES_URL/clean.png"

# Création du répertoire de quarantaine si inexistant
if [ ! -d "/quarantaine" ]; then
    sudo mkdir /quarantaine
    sudo chown clamav:clamav /quarantaine
fi

echo "Installation terminée avec succès."
