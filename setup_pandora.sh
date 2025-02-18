#!/bin/bash
# Ce script installe le module pypandora,
# ajoute la commande de lancement de Pandora Box dans le ~/.bashrc,
# et source le fichier ~/.bashrc pour appliquer les changements.

# 1. Installer pypandora
echo "Installation de pypandora..."
python3 -m pip install pypandora

# 2. Ajouter la commande dans ~/.bashrc si elle n'est pas déjà présente
BASHRC=~/.bashrc
COMMANDE="python3 /home/pandora/pandora-box/pandora-box.py"

echo "Ajout de la commande dans $BASHRC..."
if ! grep -Fxq "$COMMANDE" "$BASHRC"; then
    echo "$COMMANDE" >> "$BASHRC"
    echo "La commande a été ajoutée à $BASHRC"
else
    echo "La commande est déjà présente dans $BASHRC"
fi

# 3. Sourcer le ~/.bashrc pour prendre en compte les modifications
echo "Application des changements en sourçant $BASHRC..."
source "$BASHRC"

echo "Script terminé."
