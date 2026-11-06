#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Station Blanche – MODE HASH ultra-rapide (SHA-256) – V3 (avec e-mail) – Compatible Python 3.9 (Debian 11)

Modifs pour compatibilité 3.9 :
- Remplacement des annotations "str | None" par "Optional[str]".
- Remplacement des types d’annotations union équivalents.
- Utilisation de typing.Optional / List / Set / Dict là où nécessaire.

Pré-requis :
- Place `mail.py` dans le **même dossier** que ce script.
- `mail.py` n'attend **aucun argument**.
- Si tu veux attacher des logs existants, ajuste `files_to_attach` dans `mail.py` (ex: "station_blanche_hash.log" ou "station_blanche.log").
"""

import os
import sys
import time
import logging
import threading
import hashlib
import zipfile
import io
import subprocess
from datetime import datetime
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from queue import Queue, Empty
from pathlib import Path
from typing import Optional, List, Set, Dict

import os
import sys
import io
import tempfile
import urllib.request
import urllib.error
from zipfile import ZipFile, BadZipFile

import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageTk

import psutil
from logging.handlers import RotatingFileHandler

# ===================== Config =====================
WARNING_TEXT = "⚠️ L’analyse peut prendre un certain temps. Ne retirez pas la clé USB."
ANIM_INTERVAL_MS = 300
HASH_BUFFER_SIZE = 1024 * 1024  # 1 MiB
LOSS_SECONDS = 20
NO_USB_SECONDS = 10
STOP_ON_THREAT = True  # arrêt immédiat au 1er hash match

# E-mail (lancement de mail.py)
EMAIL_ENABLED = True
MAIL_SCRIPT = "mail.py"  # doit être dans le même dossier que ce script

# Dossier des bases de hash
HASH_DB_DIR = Path("hashdb")
LOCAL_HASH_FILE = Path("local_hashes.txt")  # optionnel, ajouté automatiquement s'il existe

# Images
IMAGE_NO_USB = "/SB-Blanc/no_usb.png"
IMAGE_SCANNING = "/SB-Blanc/scanning.png"
IMAGE_INFECTED = "/SB-Blanc/infected.png"
IMAGE_CLEAN = "/SB-Blanc/clean.png"
IMAGE_LOST = "/SB-Blanc/perte.png"

# Logs
LOG_FILE = "station_blanche_hash.log"
EVENT_LOG = "LOG.txt"

# ===================== Logging =====================
logger = logging.getLogger("station_blanche_hash")
logger.setLevel(logging.INFO)
_formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
_handler_rot = RotatingFileHandler(LOG_FILE, maxBytes=5*1024*1024, backupCount=3, encoding='utf-8')
_handler_rot.setFormatter(_formatter)
_stream = logging.StreamHandler(sys.stdout)
_stream.setFormatter(_formatter)
logger.addHandler(_handler_rot)
logger.addHandler(_stream)

# ===================== UI =====================

ABUSECH_URL = "https://bazaar.abuse.ch/export/txt/sha256/full/"
HASH_SUBPATH = os.path.join("hashdb", "mb_full.txt")
USER_AGENT = "Mozilla/5.0 (hashdb-updater; +local)"

def _script_root() -> str:
    # Répertoire où se trouve le script Python
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))

def _download_bytes(url: str, timeout: int = 60) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()

def _extract_from_zip_or_plain(data: bytes) -> bytes:
    """Retourne le contenu texte (bytes) depuis un zip (premier fichier) ou tel quel si déjà texte."""
    # Essaye comme ZIP
    try:
        with ZipFile(io.BytesIO(data)) as zf:
            # Choisit le premier fichier "texte" s'il existe, sinon le premier tout court
            names = [n for n in zf.namelist() if not n.endswith("/")]
            if not names:
                raise ValueError("ZIP sans contenu fichier.")
            # Prenons le premier
            with zf.open(names[0], "r") as fh:
                return fh.read()
    except BadZipFile:
        # Pas un zip -> probablement texte brut
        return data

def update_hash_db() -> None:
    root = _script_root()
    dest_dir = os.path.join(root, os.path.dirname(HASH_SUBPATH))
    dest_path = os.path.join(root, HASH_SUBPATH)
    os.makedirs(dest_dir, exist_ok=True)

    try:
        blob = _download_bytes(ABUSECH_URL)
    except urllib.error.URLError as e:
        print(f"[ERREUR] Téléchargement échoué: {e}", file=sys.stderr)
        return

    try:
        content = _extract_from_zip_or_plain(blob)
    except Exception as e:
        print(f"[ERREUR] Extraction ZIP/texte: {e}", file=sys.stderr)
        return

    # Vérif basique : non vide et contient au moins une fin de ligne
    if not content or content.strip() == b"":
        print("[ERREUR] Contenu vide, abandon.", file=sys.stderr)
        return

    # Écriture atomique
    try:
        with tempfile.NamedTemporaryFile("wb", delete=False, dir=dest_dir) as tmp:
            tmp.write(content)
            tmp_path = tmp.name
        # Remplacement atomique
        os.replace(tmp_path, dest_path)
    finally:
        # Si os.replace a échoué, nettoyer le tmp
        try:
            if 'tmp_path' in locals() and os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except Exception:
            pass

    # Comptage rapide des lignes
    line_count = content.count(b"\n")
    print(f"[INFO] Hash DB mise à jour : {line_count} lignes -> {dest_path}")

# Exemple: lancer la MAJ au démarrage puis poursuivre ton programme
if __name__ == "__main__":
    update_hash_db()

class FastProgressWindow:
    def __init__(self, parent, total_files=0):
        self.parent = parent
        self.window = tk.Toplevel(parent)
        self.window.title("Station Blanche - Analyse")
        self.window.attributes("-fullscreen", True)
        self.window.configure(bg='#0e0e0e')

        self.total_files = max(1, total_files)
        self.processed_files = 0
        self.infected_files = 0
        self.is_scanning = True
        self.start_time = time.time()

        self.update_queue = Queue()
        self._anim_phase = 0
        self._animating_finish = False

        self.window.bind("<Escape>", self.toggle_fullscreen)
        self.window.bind("<F11>", self.toggle_fullscreen)

        self._build_ui()
        self._process_updates()
        self._animate_text()

    def toggle_fullscreen(self, event=None):
        cur = self.window.attributes("-fullscreen")
        self.window.attributes("-fullscreen", not cur)

    def _build_ui(self):
        main = tk.Frame(self.window, bg='#0e0e0e')
        main.place(relx=0.5, rely=0.45, anchor='center')

        self.warn = tk.Label(self.window, text=WARNING_TEXT, font=("Arial", 20, "bold"), fg='#ffcc00', bg='#0e0e0e')
        self.warn.place(relx=0.5, rely=0.12, anchor='center')

        title = tk.Label(main, text="🔍 ANALYSE EN COURS", font=("Arial", 32, "bold"), bg='#0e0e0e', fg='#00bcd4')
        title.pack(pady=18)

        self.anim_label = tk.Label(main, text="", font=("Arial", 18), bg='#0e0e0e', fg='#bbbbbb')
        self.anim_label.pack(pady=6)

        self.main_label = tk.Label(main, text="Initialisation...", font=("Arial", 22, "bold"), bg='#0e0e0e', fg='white')
        self.main_label.pack(pady=8)

        self.progress_bar = ttk.Progressbar(main, length=800, mode='determinate', maximum=self.total_files)
        self.progress_bar.pack(pady=14)

        results = tk.Frame(main, bg='#0e0e0e')
        results.pack(pady=8)

        self.threat_label = tk.Label(results, text="🦠 Menaces: 0", font=("Arial", 18, "bold"), bg='#0e0e0e', fg='#ffffff')
        self.threat_label.pack(pady=2)

        self.file_label = tk.Label(main, text="Préparation de l'analyse...", font=("Arial", 12), fg='#aaaaaa', bg='#0e0e0e', wraplength=900)
        self.file_label.pack(pady=6)

    def _animate_text(self):
        if not self.is_scanning:
            return
        self._anim_phase = (self._anim_phase + 1) % 4
        dots = '.' * self._anim_phase
        self.anim_label.config(text=f"Analyse en cours{dots}")
        self.window.after(ANIM_INTERVAL_MS, self._animate_text)

    def _process_updates(self):
        try:
            processed = 0
            while processed < 40:
                data = self.update_queue.get_nowait()
                self._apply_update(data)
                processed += 1
        except Empty:
            pass
        if self.is_scanning:
            self.window.after(40, self._process_updates)

    def _apply_update(self, data: dict):
        t = data.get('type')
        if t == 'progress':
            self.processed_files = min(self.total_files, data.get('processed', self.processed_files))
            if data.get('infected'):
                self.infected_files += 1
                self.threat_label.config(text=f"🦠 Menaces: {self.infected_files}")
            pct = max(0, min(100, int((self.processed_files / self.total_files) * 100)))
            self.progress_bar['value'] = self.processed_files
            self.main_label.config(text=f"{self.processed_files} / {self.total_files} fichiers ({pct}%)")
            if data.get('current_file'):
                name = os.path.basename(data['current_file'])
                if len(name) > 70:
                    name = name[:67] + '...'
                self.file_label.config(text=f"📄 {name}")
        elif t == 'total':
            self.total_files = max(1, data['total'])
            self.progress_bar['maximum'] = self.total_files
            self.main_label.config(text=f"0 / {self.total_files} fichiers (0%)")
        elif t == 'status':
            self.file_label.config(text=data['message'])
        elif t == 'animate_finish' and not self._animating_finish:
            self._animating_finish = True
            target = self.total_files
            step = max(1, (target - self.processed_files) // 25)
            def _tick():
                if self.processed_files < target:
                    self.processed_files = min(target, self.processed_files + step)
                    pct = int((self.processed_files / self.total_files) * 100)
                    self.progress_bar['value'] = self.processed_files
                    self.main_label.config(text=f"{self.processed_files} / {self.total_files} fichiers ({pct}%)")
                    self.window.after(25, _tick)
                else:
                    self._animating_finish = False
            _tick()

    def queue_update(self, **kwargs):
        try:
            self.update_queue.put_nowait(kwargs)
        except Exception:
            pass

    def show_final_status(self, threats_found: int, scan_time: float):
        self.is_scanning = False
        if threats_found > 0:
            status_text = "⚠️ MENACE DÉTECTÉE"
            status_color = '#f44336'
        else:
            status_text = "✅ ANALYSE TERMINÉE - Aucune menace"
            status_color = '#4caf50'
        self.file_label.config(text=status_text, fg=status_color)

    def close(self):
        self.is_scanning = False
        try:
            self.window.destroy()
        except Exception:
            pass

# ===================== Images helpers =====================
IMAGE_CACHE: Dict[str, ImageTk.PhotoImage] = {}

def preload_images(tk_root: tk.Tk):
    global IMAGE_CACHE
    images = [IMAGE_NO_USB, IMAGE_SCANNING, IMAGE_INFECTED, IMAGE_CLEAN, IMAGE_LOST]
    sw, sh = tk_root.winfo_screenwidth(), tk_root.winfo_screenheight()
    for img_path in images:
        try:
            if os.path.exists(img_path):
                img = Image.open(img_path)
                img = img.resize((sw, sh), Image.LANCZOS)
                IMAGE_CACHE[img_path] = ImageTk.PhotoImage(img)
                logger.info(f"✅ Image préchargée: {os.path.basename(img_path)}")
            else:
                logger.warning(f"❌ Image non trouvée: {img_path}")
        except Exception:
            logger.exception(f"Erreur préchargement {img_path}")


def update_image_cached(label_widget: tk.Label, image_path: str):
    photo = IMAGE_CACHE.get(image_path)
    if photo is not None:
        label_widget.config(image=photo, text="")
        label_widget.image = photo
    else:
        label_widget.config(image="", text=os.path.basename(image_path) or "État", fg='white', bg='#0e0e0e', font=("Arial", 28, 'bold'))


def show_image_for(label_widget: tk.Label, image_path: str, seconds: float):
    update_image_cached(label_widget, image_path)
    time.sleep(max(0.1, seconds))

# ============ Détection USB & collecte récursive ==========
previous_mounts = set()
current_mount: Optional[str] = None
last_scanned_mount: Optional[str] = None
scan_lock = threading.Lock()
scan_in_progress = threading.Event()
STOP_EVENT = threading.Event()
post_scan_state: Optional[str] = None


def get_usb_mounts() -> List[str]:
    mounts: List[str] = []
    for mp in ['/media', '/mnt']:
        if os.path.exists(mp):
            try:
                for user_dir in os.listdir(mp):
                    p1 = os.path.join(mp, user_dir)
                    if os.path.isdir(p1):
                        for dev in os.listdir(p1):
                            p2 = os.path.join(p1, dev)
                            if os.path.isdir(p2):
                                try:
                                    os.listdir(p2)
                                    mounts.append(p2)
                                except Exception:
                                    continue
            except PermissionError:
                pass
            except Exception:
                logger.exception("Erreur lecture mounts /media|/mnt")
    try:
        for part in psutil.disk_partitions(all=False):
            if ('removable' in part.opts or '/media/' in part.mountpoint or '/mnt/' in part.mountpoint):
                if os.path.exists(part.mountpoint):
                    try:
                        os.listdir(part.mountpoint)
                        mounts.append(part.mountpoint)
                    except Exception:
                        pass
    except Exception:
        logger.exception("psutil.disk_partitions failed")
    uniq, seen = [], set()
    for p in mounts:
        rp = os.path.realpath(p)
        if rp not in seen and os.path.exists(rp):
            seen.add(rp)
            uniq.append(rp)
    logger.info(f"Mounts détectés: {uniq}")
    return uniq


def collect_files(usb_path: str) -> List[str]:
    files: List[str] = []
    ignore_dirs = {'System Volume Information', '$RECYCLE.BIN', '.Trash-1000'}
    for dirpath, dirs, filenames in os.walk(usb_path):
        if not os.path.exists(usb_path):
            break
        dirs[:] = [d for d in dirs if d not in ignore_dirs and not d.startswith('.')]
        for name in filenames:
            if name.startswith('.'):
                continue
            files.append(os.path.join(dirpath, name))
    return files

# ===================== Hash DB =====================

def normalize_hash(line: str) -> Optional[str]:
    s = line.strip().lower()
    if not s:
        return None
    for sep in (' ', '\t', ',', ';', '|'):
        if sep in s:
            s = s.split(sep, 1)[0]
    if len(s) == 64 and all(c in '0123456789abcdef' for c in s):
        return s
    return None


def load_hash_db(paths: List[Path]) -> Set[str]:
    hashes: Set[str] = set()
    for p in paths:
        try:
            if p.is_file():
                with p.open('r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        h = normalize_hash(line)
                        if h:
                            hashes.add(h)
            elif p.is_dir():
                for child in sorted(p.rglob('*')):
                    if child.is_file():
                        try:
                            with child.open('r', encoding='utf-8', errors='ignore') as f:
                                for line in f:
                                    h = normalize_hash(line)
                                    if h:
                                        hashes.add(h)
                        except Exception:
                            logger.exception(f"Lecture DB: {child}")
        except Exception:
            logger.exception(f"Lecture DB: {p}")
    logger.info(f"DB hash chargée: {len(hashes)} entrées uniques")
    return hashes

# ===================== Hashing =====================

def sha256_file(path: str) -> Optional[str]:
    h = hashlib.sha256()
    try:
        with open(path, 'rb') as f:
            while True:
                chunk = f.read(HASH_BUFFER_SIZE)
                if not chunk:
                    break
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return None

# ===================== E-mail helper =====================

def notify_email_async():
    """Lance mail.py en asynchrone si présent et si EMAIL_ENABLED=True."""
    if not EMAIL_ENABLED:
        return
    script_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), MAIL_SCRIPT)
    if os.path.exists(script_path):
        try:
            threading.Thread(
                target=lambda: subprocess.run([sys.executable, script_path], timeout=60),
                daemon=True
            ).start()
            logger.info("mail.py lancé en arrière-plan")
        except Exception:
            logger.exception("Échec lancement mail.py")
    else:
        logger.warning(f"mail.py introuvable à {script_path}")

# ===================== Scan (mode hash) =====================

def scan_hash_mode(tk_root: tk.Tk, status_label: tk.Label, usb_path: str, db_hashes: Set[str]):
    global post_scan_state
    STOP_EVENT.clear()
    update_image_cached(status_label, IMAGE_SCANNING)

    all_files = collect_files(usb_path)
    total = len(all_files)
    logger.info(f"Cible: {usb_path} — Total fichiers: {total}")

    prog = FastProgressWindow(tk_root, total_files=total)
    prog.queue_update(type='total', total=total)
    prog.queue_update(type='status', message=f'Analyse de {total} fichiers…')

    infected_paths = []
    processed = 0
    shown_infected_once = False

    def _show_infected_immediately():
        nonlocal shown_infected_once
        if not shown_infected_once:
            shown_infected_once = True
            update_image_cached(status_label, IMAGE_INFECTED)
            globals()['post_scan_state'] = 'infected'
            prog.queue_update(type='animate_finish')

    try:
        for fp in all_files:
            if not os.path.exists(usb_path):
                logger.warning("USB déconnectée pendant le scan")
                prog.close()
                show_image_for(status_label, IMAGE_LOST, LOSS_SECONDS)
                show_image_for(status_label, IMAGE_NO_USB, NO_USB_SECONDS)
                post_scan_state = None
                return 'disconnected'

            if STOP_EVENT.is_set():
                break

            digest = sha256_file(fp)
            processed += 1

            if digest and digest in db_hashes:
                infected_paths.append(fp)
                _show_infected_immediately()
                prog.queue_update(type='progress', processed=processed, current_file=fp, infected=True)
                # e-mail
                notify_email_async()
                if STOP_ON_THREAT:
                    STOP_EVENT.set()
                    break
            else:
                prog.queue_update(type='progress', processed=processed, current_file=fp)

    except Exception:
        logger.exception("Erreur générale du scan (HASH)")

    threats = len(infected_paths)
    time.sleep(0.6)
    prog.show_final_status(threats, max(0.1, time.time() - prog.start_time))
    time.sleep(0.8)
    prog.close()

    if threats:
        update_image_cached(status_label, IMAGE_INFECTED)
        post_scan_state = 'infected'
        log_infection_event(usb_path, f"{threats} menace(s) détectée(s) (HASH)")
    else:
        update_image_cached(status_label, IMAGE_CLEAN)
        post_scan_state = 'clean'

    return 'done_infected' if threats else 'done_clean'

# ===================== Logs/compteur & boucle =====================

def log_infection_event(usb_mount: str, scan_result: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    usb_id = os.path.basename(usb_mount.rstrip(os.sep)) or usb_mount
    entry = f"[{ts}] USB: {usb_id} - {scan_result}\n{'-'*50}\n"
    try:
        with open(EVENT_LOG, "a", encoding='utf-8') as f:
            f.write(entry)
        logger.info(f"Infection loggée: {usb_id}")
    except Exception:
        logger.exception("Erreur écriture event log")


def increment_usb_counter(path_file: str = "NBCLE.txt"):
    count = 0
    try:
        if os.path.exists(path_file):
            with open(path_file, 'r', encoding='utf-8') as f:
                first = f.readline().strip()
                if first:
                    count = int(first.split(": ")[1])
    except Exception:
        count = 0
    count += 1
    try:
        with open(path_file, 'w', encoding='utf-8') as f:
            f.write(f"Nombre total de clés USB connectées : {count}\n")
        logger.info(f"USB #{count} connectée")
    except Exception:
        logger.exception("Erreur écriture stats")


def main_loop_hash(tk_root: tk.Tk, status_label: tk.Label, db_hashes: Set[str]):
    global current_mount, last_scanned_mount, post_scan_state
    logger.info("🚀 Démarrage de la boucle principale (MODE HASH)")
    while True:
        try:
            mounts = get_usb_mounts()
            new_mounts = [m for m in mounts if m not in previous_mounts]
            removed = [m for m in previous_mounts if m not in mounts]

            if removed:
                logger.info(f"USB retirée(s): {removed}")
                show_image_for(status_label, IMAGE_NO_USB, NO_USB_SECONDS)
                post_scan_state = None
                for r in removed:
                    if r == last_scanned_mount:
                        last_scanned_mount = None

            if new_mounts:
                logger.info(f"🔌 Nouvelles USB: {new_mounts}")
                increment_usb_counter()

            previous_mounts.clear(); previous_mounts.update(mounts)
            current_mount = mounts[0] if mounts else None

            if current_mount and post_scan_state in ('clean', 'infected'):
                pass
            elif not mounts and post_scan_state is None:
                update_image_cached(status_label, IMAGE_NO_USB)

            if (not scan_in_progress.is_set()) and current_mount and (current_mount != last_scanned_mount):
                if scan_lock.acquire(blocking=False):
                    scan_in_progress.set(); STOP_EVENT.clear()
                    def _run():
                        global last_scanned_mount
                        try:
                            logger.info(f"→ Lancement scan (HASH): {current_mount}")
                            result = scan_hash_mode(tk_root, status_label, current_mount, db_hashes)
                            if result == 'disconnected':
                                last_scanned_mount = None
                            else:
                                last_scanned_mount = current_mount
                        finally:
                            scan_in_progress.clear()
                            scan_lock.release()
                    threading.Thread(target=_run, daemon=True).start()

            time.sleep(1)
        except Exception:
            logger.exception("Erreur boucle principale")
            time.sleep(2)

# ===================== Updater (MalwareBazaar) =====================
USER_AGENT = "StationBlancheHash/1.0 (+https://bazaar.abuse.ch/export/)"
URL_RECENT_SHA256 = "https://bazaar.abuse.ch/export/txt/sha256/recent/"
URL_FULL_SHA256 = "https://bazaar.abuse.ch/export/txt/sha256/full/"  # zip


def fetch_url(url: str) -> bytes:
    req = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(req, timeout=120) as resp:
        return resp.read()


def update_recent(out_path: Path):
    try:
        data = fetch_url(URL_RECENT_SHA256)
        text = data.decode('utf-8', errors='ignore')
        lines = [normalize_hash(l) for l in text.splitlines()]
        hashes = sorted({h for h in lines if h})
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open('w', encoding='utf-8') as f:
            for h in hashes:
                f.write(h + "\n")
        logger.info(f"✅ recent: écrit {len(hashes)} hachés dans {out_path}")
    except (HTTPError, URLError) as e:
        logger.error(f"Téléchargement recent a échoué: {e}")
    except Exception:
        logger.exception("update_recent")


def update_full(out_path: Path):
    try:
        data = fetch_url(URL_FULL_SHA256)
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            name = next((n for n in zf.namelist() if n.lower().endswith('.txt')), None)
            if not name:
                raise RuntimeError("Zip sans .txt")
            txt = zf.read(name).decode('utf-8', errors='ignore')
        lines = [normalize_hash(l) for l in txt.splitlines()]
        hashes = sorted({h for h in lines if h})
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open('w', encoding='utf-8') as f:
            for h in hashes:
                f.write(h + "\n")
        logger.info(f"✅ full: écrit {len(hashes)} hachés dans {out_path}")
    except (HTTPError, URLError) as e:
        logger.error(f"Téléchargement full a échoué: {e}")
    except zipfile.BadZipFile:
        logger.exception("update_full: zip invalide")
    except Exception:
        logger.exception("update_full")

# ===================== Entrée =====================

def run_gui():
    # Charger la DB
    paths: List[Path] = [HASH_DB_DIR]
    if LOCAL_HASH_FILE.exists():
        paths.append(LOCAL_HASH_FILE)
    db = load_hash_db(paths)

    tk_root = tk.Tk()
    tk_root.title("Station Blanche")
    tk_root.attributes("-fullscreen", True)

    def exit_fullscreen(event=None):
        tk_root.attributes("-fullscreen", False)
        try:
            tk_root.destroy()
        except Exception:
            pass

    tk_root.bind("<Escape>", exit_fullscreen)

    status_label = tk.Label(tk_root)
    status_label.pack()

    preload_images(tk_root)
    update_image_cached(status_label, IMAGE_NO_USB)

    threading.Thread(target=main_loop_hash, args=(tk_root, status_label, db), daemon=True).start()
    tk_root.mainloop()


def main():
    import argparse
    p = argparse.ArgumentParser(description="Station Blanche – Mode Hash (SHA256)")
    sub = p.add_subparsers(dest='cmd', required=True)

    sub.add_parser('gui', help='Lancer l\'interface graphique (scan USB)')

    pu = sub.add_parser('update', help='Télécharger une base de SHA256 (MalwareBazaar)')
    g = pu.add_mutually_exclusive_group(required=True)
    g.add_argument('--recent', action='store_true', help='Télécharger les 48h récentes (plain text)')
    g.add_argument('--full', action='store_true', help='Télécharger le dump complet (zip)')
    pu.add_argument('--out', type=str, required=True, help='Chemin du fichier de sortie (ex: hashdb/mb_recent.txt)')

    args = p.parse_args()
    if args.cmd == 'gui':
        run_gui()
    elif args.cmd == 'update':
        out = Path(args.out)
        if args.recent:
            update_recent(out)
        elif args.full:
            update_full(out)

if __name__ == "__main__":
    main()
