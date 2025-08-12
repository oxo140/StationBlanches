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
  clamav wget curl python3-pyudev unzip python3-psutil xdg-user-dirs


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
(
  cd "$INSTALL_DIR"
  curl -O "$IMAGE_REPO/script.py"
  curl -O "$IMAGE_REPO/script_monitor.sh"
  curl -O "$IMAGE_REPO/usb_monitor.py"
)
chmod +x "$INSTALL_DIR/script_monitor.sh"


# === Module Mail Optionnel ===
echo ""
echo "=== MODULE MAIL ==="
echo "Le module mail permet d'envoyer des rapports de scan par email."
read -p "Voulez-vous installer le module mail ? (O/n) : " INSTALL_MAIL
INSTALL_MAIL=${INSTALL_MAIL:-O}

if [[ "$INSTALL_MAIL" =~ ^[Oo]$ ]] || [[ "$INSTALL_MAIL" == "oui" ]] || [[ "$INSTALL_MAIL" == "yes" ]]; then
    echo "[INFO] Installation du module mail..."
    MAIL_INSTALL_SCRIPT="$(mktemp)"
    wget -O "$MAIL_INSTALL_SCRIPT" "https://raw.githubusercontent.com/oxo140/StationBlanches/main/mailinstall.sh"
    if [ -f "$MAIL_INSTALL_SCRIPT" ] && [ -s "$MAIL_INSTALL_SCRIPT" ]; then
        chmod +x "$MAIL_INSTALL_SCRIPT"
        echo "[INFO] Lancement du script d'installation mail..."
        "$MAIL_INSTALL_SCRIPT"
        rm -f "$MAIL_INSTALL_SCRIPT"
        echo "[INFO] Installation du module mail terminée."
    else
        echo "[WARN] Impossible de télécharger le script d'installation mail."
        echo "[WARN] Installation continuée sans le module mail."
    fi
else
    echo "[INFO] Module mail non installé."
fi

# === Crons shutdown ===

(crontab -l 2>/dev/null; echo "0 22 * * * sudo shutdown -h now") | crontab -

# === Nom utilisateur cible (pour autostart GUI) ===
ACTIVE_USER=$(who | awk '{print $1}' | head -n 1 || true)
if [ -z "${ACTIVE_USER:-}" ]; then
  ACTIVE_USER="$SUDO_USER"
fi
echo "Utilisateur détecté : ${ACTIVE_USER:-inconnu}"
read -p "Utilisateur pour l'autostart GUI (${ACTIVE_USER:-root}) : " USERNAME
USERNAME=${USERNAME:-${ACTIVE_USER:-root}}
echo "[INFO] Utilisateur sélectionné : $USERNAME"

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
if [ -z "$USER_HOME" ]; then
  echo "[ERREUR] Impossible de déterminer le HOME de $USERNAME"
  exit 1
fi

# === Autostart GUI (XDG) ===
echo "[INFO] Création de l'autostart GUI (XDG)..."
AUTOSTART_DIR="$USER_HOME/.config/autostart"
sudo -u "$USERNAME" mkdir -p "$AUTOSTART_DIR"

DESKTOP_FILE="$AUTOSTART_DIR/station-blanche-gui.desktop"
cat <<EOF | sudo tee "$DESKTOP_FILE" >/dev/null
[Desktop Entry]
Type=Application
Name=Station Blanche
Comment=Lance l'interface graphique de Station Blanche
Exec=/usr/bin/env python3 "$SCRIPT_PATH" gui
Icon=$IMAGES_DIR/clean.png
Terminal=false
X-GNOME-Autostart-enabled=true
X-KDE-autostart-after=panel
OnlyShowIn=GNOME;KDE;XFCE;LXDE;LXQt;MATE;Cinnamon;Unity;
EOF
sudo chown "$USERNAME":"$USERNAME" "$DESKTOP_FILE"

# === (Optionnel) Services systemd utilisateur pour les scripts non-GUI ===
# Tu pourras ajouter ici des unités --user si tu veux que des daemons tournent en arrière-plan.
# On laisse juste le "linger" prêt si tu en as besoin.
echo "[INFO] Activation du linger utilisateur (optionnel pour timers/daemons en arrière-plan)..."
sudo loginctl enable-linger "$USERNAME" || true

# === Permissions utiles ===
chmod 777 "$HASH_DIR" || true
touch "$INSTALL_DIR/station_blanche_hash.log" && chmod 666 "$INSTALL_DIR/station_blanche_hash.log" || true

# === Fin ===
echo "[INFO] Installation terminée."
echo ""
echo "=== Vérifs / Utilisation ==="
echo "- L'UI se lancera automatiquement à la connexion de $USERNAME dans sa session graphique."
echo "- Test manuel : /usr/bin/env python3 \"$SCRIPT_PATH\" gui"
echo "- Autostart : $DESKTOP_FILE"
echo "- Hash update manuel : \"$INSTALL_DIR/update_hashdb.sh\""
echo "- Cron : freshclam à 21:00, shutdown à 22:00 (crontab utilisateur)."
