#!/bin/bash

# Fonction d'information
info() {
    echo "[INFO] $1"
}

# Mettre à jour les dépôts et les paquets
info "Mise à jour des dépôts et des paquets"
sudo apt update && sudo apt upgrade -y

# Installer les dépendances nécessaires
info "Installation des dépendances nécessaires"
sudo apt install -y git python3 python3-pip python3-tk python3-pil python3-pil.imagetk clamav wget curl

# Activer et démarrer le service clamav-freshclam
info "Activation et démarrage du service clamav-freshclam"
sudo systemctl enable clamav-freshclam
sudo systemctl start clamav-freshclam

# Mise à jour de la base de données ClamAV
info "Mise à jour de la base de données ClamAV"
sudo freshclam

# Création du répertoire d'images si inexistant
if [ ! -d "/SB-Blanc" ]; then
    info "Création du répertoire /SB-Blanc"
    sudo mkdir /SB-Blanc
fi

# Téléchargement des images depuis le dépôt GitHub
IMAGES_URL="https://raw.githubusercontent.com/oxo140/StationBlanches/main"
info "Téléchargement des images depuis le dépôt GitHub"
wget -O /SB-Blanc/no_usb.png "$IMAGES_URL/no_usb.png"
wget -O /SB-Blanc/scanning.png "$IMAGES_URL/scanning.png"
wget -O /SB-Blanc/infected.png "$IMAGES_URL/infected.png"
wget -O /SB-Blanc/clean.png "$IMAGES_URL/clean.png"
wget -O /SB-Blanc/perte.png "$IMAGES_URL/perte.png" 

# Téléchargement du script Python depuis GitHub
info "Téléchargement du script Python depuis GitHub"
curl -O "$IMAGES_URL/script.py"  # Télécharger le script Python

# Création du répertoire de quarantaine si inexistant
if [ ! -d "/quarantaine" ]; then
    info "Création du répertoire /quarantaine"
    sudo mkdir /quarantaine
    sudo chown clamav:clamav /quarantaine
fi

# Demande à l'utilisateur si une configuration d'arrêt automatique est souhaitée
echo "Souhaitez-vous configurer un arrêt automatique ? (oui/non)"
read config_arret

if [ "$config_arret" == "oui" ]; then
    # Demander l'heure d'arrêt en format français hh:mm
    echo "À quelle heure souhaitez-vous que l'arrêt automatique ait lieu ? (format: hh:mm)"
    read heure_arret

    # Vérification de la validité du format
    if [[ "$heure_arret" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
        info "Heure d'arrêt saisie : $heure_arret"
        
        # Ajouter la tâche cron pour l'arrêt automatique
        echo "$heure_arret root /sbin/shutdown -h now" | sudo tee -a /etc/crontab
        info "Configuration d'arrêt automatique enregistrée pour $heure_arret."
    else
        info "Format d'heure invalide. L'arrêt automatique n'a pas été configuré."
        echo "Format d'heure invalide. L'arrêt automatique n'a pas été configuré."
    fi
fi

# Ajouter le script Python au démarrage via crontab
info "Ajout du script Python au démarrage"
(crontab -l 2>/dev/null; echo "@reboot /usr/bin/python3 /SB-Blanc/script.py") | crontab -

# Ajouter une mise à jour automatique de ClamAV tous les jours à 13h30
info "Configuration de la mise à jour automatique de ClamAV à 13h30 tous les jours"
echo "30 13 * * * root /usr/bin/freshclam" | sudo tee -a /etc/crontab

info "Installation et configuration terminées avec succès."
echo "Installation et configuration terminées avec succès."
echo "Une mise à jour automatique de ClamAV a été configurée pour s'exécuter tous les jours à 13h30."
