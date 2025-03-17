import os
import time
import subprocess
import tkinter as tk
from PIL import Image, ImageTk
import threading

# Chemins vers les images d'état
IMAGE_NO_USB = "/SB-Blanc/no_usb.png"
IMAGE_SCANNING = "/SB-Blanc/scanning.png"
IMAGE_INFECTED = "/SB-Blanc/infected.png"
IMAGE_CLEAN = "/SB-Blanc/clean.png"
IMAGE_LOST = "/SB-Blanc/perte.png"  # Image à afficher si la clé est arrachée pendant l'analyse

# Dossier de quarantaine (en cas d'infection)
QUARANTINE_DIR = "/quarantaine/"

# Variable pour suivre l'état précédent
previous_usb_path = None

# Fonction pour vérifier la présence d'une clé USB via /proc/mounts
def get_usb_path():
    print("[DEBUG] Vérification des périphériques USB via /proc/mounts...")
    with open("/proc/mounts", "r") as mounts:
        for line in mounts:
            if "/media/" in line or "/mnt/" in line:
                usb_path = line.split()[1]  # Récupère le point de montage
                print(f"[DEBUG] Clé USB détectée : {usb_path}")
                return usb_path
    print("[DEBUG] Aucune clé USB détectée.")
    return None

# Fonction de mise à jour de l'image affichée
def update_image(image_path):
    print(f"[DEBUG] Affichage de l'image : {image_path}")
    img = Image.open(image_path)
    img = img.resize((root.winfo_screenwidth(), root.winfo_screenheight()), Image.LANCZOS)  # Plein écran + qualité optimale
    photo = ImageTk.PhotoImage(img)
    label.config(image=photo)
    label.image = photo  # Mise à jour de l'image affichée

# Fonction de scan de la clé USB
def scan_usb(usb_path):
    print(f"[DEBUG] Démarrage de l'analyse antivirus sur : {usb_path}")
    update_image(IMAGE_SCANNING)
    
    # Vérifier si la clé USB est toujours présente avant de commencer le scan
    if not os.path.exists(usb_path):
        update_image(IMAGE_LOST)
        print("[DEBUG] Clé USB retirée avant le début du scan.")
        return
    
    result = subprocess.run(
        ["clamscan", "-r", usb_path, "--move=" + QUARANTINE_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    # Vérification si la clé USB a été retirée pendant l'analyse
    if not os.path.exists(usb_path):
        update_image(IMAGE_LOST)
        print("[DEBUG] Clé USB retirée pendant l'analyse.")
        return

    print("[DEBUG] Résultat de l'analyse :")
    print(result.stdout.decode())  # Affiche le résultat du scan dans le terminal pour le debug

    if "Infected files: 0" in result.stdout.decode():
        print("[DEBUG] Aucun fichier infecté détecté.")
        update_image(IMAGE_CLEAN)
    else:
        print("[DEBUG] Des fichiers infectés ont été détectés !")
        update_image(IMAGE_INFECTED)

    time.sleep(2)  # Attente de 2 secondes avant de revenir à l'état initial

# Fonction principale de boucle (exécutée dans un thread séparé)
def main_loop():
    global previous_usb_path
    while True:
        usb_path = get_usb_path()

        if usb_path != previous_usb_path:
            if usb_path:
                scan_usb(usb_path)
            else:
                update_image(IMAGE_NO_USB)

        previous_usb_path = usb_path
        time.sleep(2)  # Vérification toutes les 2 secondes

# Interface graphique Tkinter
root = tk.Tk()
root.title("Station Blanche - Scan USB")

# Activer le mode plein écran
root.attributes("-fullscreen", True)

# Permettre de quitter avec la touche Échap
def exit_fullscreen(event=None):
    root.attributes("-fullscreen", False)
    root.destroy()

root.bind("<Escape>", exit_fullscreen)

# Zone d'affichage de l'image
label = tk.Label(root)
label.pack()

# Afficher "no_usb" au lancement
update_image(IMAGE_NO_USB)

# Démarrage de la boucle principale dans un thread séparé
def start_thread():
    thread = threading.Thread(target=main_loop, daemon=True)
    thread.start()

# Lancer le thread après l'initialisation de l'interface
root.after(100, start_thread)

# Démarrer Tkinter
root.mainloop()
