#!/bin/bash

# Mettre à jour les paquets et installer les dépendances nécessaires
echo "Mise à jour des paquets et installation des dépendances..."
sudo apt-get update
sudo apt-get install -y python3 python3-pip msmtp curl

# Télécharger le script Python depuis l'URL fournie
echo "Téléchargement du script Python..."
curl -O https://raw.githubusercontent.com/oxo140/StationBlanches/main/mail.py

# Demander à l'utilisateur les informations nécessaires
echo "Veuillez entrer l'email de l'expéditeur (votre email Gmail) :"
read from_email

echo "Veuillez entrer l'email du destinataire :"
read to_email

echo "Veuillez entrer le mot de passe d'application Gmail :"
read app_password

# Modifier le fichier mail.py avec les nouvelles informations
echo "Modification du script mail.py avec vos informations..."
sed -i "s/from_email = .*/from_email = \"$from_email\"/" mail.py
sed -i "s/to_email = .*/to_email = \"$to_email\"/" mail.py
sed -i "s/server.login(from_email, .*/server.login(from_email, '$app_password')/" mail.py

# Créer ou modifier le fichier .msmtprc
echo "Configuration de msmtp..."

cat << EOF > ~/.msmtprc
account default
host smtp.gmail.com
port 587
auth on
user $from_email
password $app_password
tls on
tls_starttls on
logfile ~/.msmtp.log
EOF

# Assurer que les permissions du fichier .msmtprc sont sécurisées
chmod 600 ~/.msmtprc

# Afficher un message pour l'utilisateur
echo "L'installation et la configuration sont terminées."
echo "Le script mail.py a été téléchargé et modifié avec vos informations."



