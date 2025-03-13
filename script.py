import os
import time
import subprocess
import tkinter as tk
from PIL import Image, ImageTk
import threading
import signal
import sys

# Chemins vers les images d'état
IMAGE_NO_USB = "/SB-Blanc/no_usb.png"
IMAGE_SCANNING = "/SB-Blanc/scanning.png"
IMAGE_INFECTED = "/SB-Blanc/infected.png"
IMAGE_CLEAN = "/SB-Blanc/clean.png"

# Dossier de quarantaine (en cas d'infection)
QUARANTINE_DIR = "/quarantaine/"

# Fonction pour vérifier la présence d'une clé USB
def get_usb_path():
    media_path = "/media/"
    for root, dirs, files in os.walk(media_path):
        if dirs:
            return os.path.join(media_path, dirs[0])  # Retourne le chemin de la clé USB
    return None

# Fonction de mise à jour de l'image affichée
def update_image(image_path):
    try:
        img = Image.open(image_path)
        img = img.resize((800, 600), Image.LANCZOS)  # Taille fixe pour tester
        photo = ImageTk.PhotoImage(img)
        label.config(image=photo)
        label.image = photo  # Mise à jour de l'image affichée
    except Exception as e:
        print(f"Erreur lors du chargement de l'image : {e}")
        update_image(IMAGE_NO_USB)  # Afficher l'image par défaut en cas d'erreur

# Fonction de scan de la clé USB
def scan_usb(usb_path):
    update_image(IMAGE_SCANNING)  # Afficher l'image de scanning dès que le scan commence
    try:
        result = subprocess.run(
            ["clamscan", "-r", usb_path, "--move=" + QUARANTINE_DIR],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        if "Infected files: 0" in result.stdout.decode():
            update_image(IMAGE_CLEAN)
        else:
            update_image(IMAGE_INFECTED)
    except Exception as e:
        print(f"Erreur lors du scan de la clé USB : {e}")
        update_image(IMAGE_NO_USB)

# Fonction principale de boucle (en thread)
def main_loop():
    # Initialement, afficher l'image "no USB"
    update_image(IMAGE_NO_USB)
    
    previous_usb_path = None  # Variable pour garder en mémoire la clé USB précédente
    
    while True:
        usb_path = get_usb_path()

        if usb_path and usb_path != previous_usb_path:
            # Une nouvelle clé USB est détectée
            previous_usb_path = usb_path
            scan_usb(usb_path)
        elif not usb_path and previous_usb_path:
            # La clé USB a été retirée
            previous_usb_path = None
            update_image(IMAGE_NO_USB)  # Retour à "no USB" lorsqu'aucune clé n'est détectée

        time.sleep(2)  # Vérification toutes les 2 secondes

# Gestion de l'interruption (Ctrl + C)
def handle_signal(signal, frame):
    print("\nArrêt du programme...")
    root.quit()  # Arrêter proprement l'interface Tkinter
    sys.exit(0)  # Sortir du programme

# Interface graphique Tkinter
root = tk.Tk()
root.title("Station Blanche - Scan USB")

# Activer le mode plein écran
root.attributes("-fullscreen", True)

# Permettre de quitter avec la touche Échap
def exit_fullscreen(event=None):
    root.attributes("-fullscreen", False)
    root.quit()

root.bind("<Escape>", exit_fullscreen)

# Zone d'affichage de l'image
label = tk.Label(root)
label.pack()

# Lancer le thread pour la boucle principale
thread = threading.Thread(target=main_loop, daemon=True)
thread.start()

# Gérer le signal d'interruption pour arrêter proprement le programme
signal.signal(signal.SIGINT, handle_signal)

# Démarrer Tkinter
root.mainloop()
