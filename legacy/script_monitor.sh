#!/bin/bash
export DISPLAY=:0

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
