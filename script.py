import os
import time
import subprocess
import tkinter as tk
from PIL import Image, ImageTk
import threading
from datetime import datetime

# Chemins vers les images d'état
IMAGE_NO_USB = "/SB-Blanc/no_usb.png"
IMAGE_SCANNING = "/SB-Blanc/scanning.png"
IMAGE_INFECTED = "/SB-Blanc/infected.png"
IMAGE_CLEAN = "/SB-Blanc/clean.png"
IMAGE_LOST = "/SB-Blanc/perte.png"

# Dossier de quarantaine (en cas d'infection)
QUARANTINE_DIR = "/quarantaine/"

# Fichiers log
LOG_FILE = "log.txt"
STATS_FILE = "stats.txt"

# Variable pour suivre l'état précédent
previous_usb_path = None
usb_count = 0

def log_infection(usb_path, scan_result):
    """Crée ou ajoute un log en cas de détection de virus."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    usb_id = usb_path.split("/")[-1]  # Utilise le nom du point de montage comme ID de clé
    with open(LOG_FILE, "a") as log_file:
        log_file.write(f"[{timestamp}] Infection détectée sur la clé ID: {usb_id}\n")
        log_file.write(scan_result + "\n")
        log_file.write("-" * 40 + "\n")

def log_usb_connection():
    """Enregistre chaque clé USB connectée."""
    global usb_count
    usb_count += 1
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(STATS_FILE, "w") as stats_file:
        stats_file.write(f"Nombre total de clés USB connectées : {usb_count}\n")
    with open(STATS_FILE, "a") as stats_file:
        stats_file.write(f"[{timestamp}] Clé USB connectée\n")

# Fonction pour vérifier la présence d'une clé USB via /proc/mounts
def get_usb_path():
    with open("/proc/mounts", "r") as mounts:
        for line in mounts:
            if "/media/" in line or "/mnt/" in line:
                usb_path = line.split()[1]  # Récupère le point de montage
                return usb_path
    return None

# Fonction de mise à jour de l'image affichée
def update_image(image_path):
    img = Image.open(image_path)
    img = img.resize((root.winfo_screenwidth(), root.winfo_screenheight()), Image.LANCZOS)
    photo = ImageTk.PhotoImage(img)
    label.config(image=photo)
    label.image = photo

# Fonction de scan de la clé USB
def scan_usb(usb_path):
    global previous_usb_path
    update_image(IMAGE_SCANNING)

    if not os.path.exists(usb_path):
        update_image(IMAGE_LOST)
        time.sleep(5)
        update_image(IMAGE_NO_USB)
        return

    result = subprocess.run(
        ["clamscan", "-r", usb_path, "--move=" + QUARANTINE_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    if not os.path.exists(usb_path):
        update_image(IMAGE_LOST)
        time.sleep(10)
        update_image(IMAGE_NO_USB)
        return

    scan_result = result.stdout.decode()

    if "Infected files: 0" in scan_result:
        update_image(IMAGE_CLEAN)
    else:
        update_image(IMAGE_INFECTED)
        log_infection(usb_path, scan_result)

    time.sleep(2)

def main_loop():
    global previous_usb_path
    while True:
        usb_path = get_usb_path()

        if usb_path != previous_usb_path:
            if usb_path:
                log_usb_connection()
                scan_usb(usb_path)
            else:
                update_image(IMAGE_NO_USB)

        previous_usb_path = usb_path
        time.sleep(2)

root = tk.Tk()
root.title("Station Blanche - Scan USB")
root.attributes("-fullscreen", True)

def exit_fullscreen(event=None):
    root.attributes("-fullscreen", False)
    root.destroy()

root.bind("<Escape>", exit_fullscreen)

label = tk.Label(root)
label.pack()

update_image(IMAGE_NO_USB)

def start_thread():
    thread = threading.Thread(target=main_loop, daemon=True)
    thread.start()

root.after(100, start_thread)
root.mainloop()
