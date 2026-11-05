#!/usr/bin/python3
"""Configure la session kiosque sans enregistrer ni modifier de mot de passe."""
import configparser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

DESKTOPS = {
    "GNOME": ("gnome-session",), "GNOME Flashback": ("gnome-panel",),
    "Xfce": ("xfce4-session",), "KDE Plasma": ("startplasma-wayland", "startplasma-x11"),
    "Cinnamon": ("cinnamon-session",), "MATE": ("mate-session",),
    "LXDE": ("lxsession",), "LXQt": ("startlxqt",),
}


def installed_desktops(which=shutil.which):
    return [name for name, commands in DESKTOPS.items() if any(which(cmd) for cmd in commands)]


def manager_name(text):
    name = Path(text.strip()).name
    return {"gdm3": "gdm3", "gdm": "gdm3", "lightdm": "lightdm", "sddm": "sddm", "lxdm": "lxdm"}.get(name)


def merge_ini(text, section, values):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if text.strip():
        parser.read_string(text)
    if not parser.has_section(section):
        parser.add_section(section)
    for key, value in values.items():
        parser.set(section, key, str(value))
    import io
    output = io.StringIO()
    parser.write(output, space_around_delimiters=False)
    return output.getvalue()


def write_config(path, text):
    path = Path(path)
    backup = Path("/var/lib/station-blanche/desktop-backups") / str(path).lstrip("/")
    if path.exists() and not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".station-blanche.tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.chmod(0o644)
    temporary.replace(path)


def configure_manager(manager, user, read, write, sessions, preferred_session=None):
    if manager == "gdm3":
        path, section, values = "/etc/gdm3/daemon.conf", "daemon", {"AutomaticLoginEnable": "true", "AutomaticLogin": user}
    elif manager == "lightdm":
        # Le fichier principal a priorité sur les drop-ins LightDM.
        path, section, values = "/etc/lightdm/lightdm.conf", "Seat:*", {"autologin-user": user, "autologin-user-timeout": "0"}
    elif manager == "sddm":
        path, section, values = "/etc/sddm.conf", "Autologin", {"User": user, "Relogin": "true"}
        current = configparser.ConfigParser(interpolation=None, strict=False)
        current.read_string(read(path) or "")
        if not current.get("Autologin", "Session", fallback=""):
            if not sessions:
                raise RuntimeError("SDDM : aucune session graphique installée détectée")
            # Plasma est le choix Debian habituel de SDDM ; conserver une session déjà définie.
            values["Session"] = preferred_session if preferred_session in sessions else next((s for s in sessions if "plasma" in s), sessions[0])
    elif manager == "lxdm":
        path, section, values = "/etc/lxdm/lxdm.conf", "base", {"autologin": user}
    else:
        raise RuntimeError("Gestionnaire de connexion non pris en charge : GDM3, LightDM, SDDM ou LXDM requis")
    write(path, merge_ini(read(path), section, values))


def main():
    import pwd
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise RuntimeError("Utilisation : sudo python3 desktop-config.py UTILISATEUR_BUREAU")
    account = pwd.getpwnam(sys.argv[1])
    if account.pw_uid == 0 or account.pw_shell.endswith(("nologin", "false")):
        raise RuntimeError("Un compte bureau non root est requis")
    read = lambda path: Path(path).read_text() if Path(path).is_file() else ""
    manager = manager_name(read("/etc/X11/default-display-manager"))
    if manager is None:
        try:
            manager = manager_name(os.path.realpath("/etc/systemd/system/display-manager.service").removesuffix(".service"))
        except OSError:
            pass
    sessions = sorted({p.name for folder in ("/usr/share/wayland-sessions", "/usr/share/xsessions") for p in Path(folder).glob("*.desktop")})
    preferred = None
    for file, section, keys in ((Path(account.pw_dir) / ".dmrc", "Desktop", ("Session",)),
                                (Path("/var/lib/AccountsService/users") / account.pw_name, "User", ("XSession", "Session")),
                                (Path("/var/lib/sddm/state.conf"), "Last", ("Session",))):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.read(file)
        for key in keys:
            value = parser.get(section, key, fallback="")
            candidate = Path(value).name
            if candidate and not candidate.endswith(".desktop"):
                candidate += ".desktop"
            if candidate in sessions and preferred is None:
                preferred = candidate
    configure_manager(manager, account.pw_name, read, write_config, sessions, preferred)
    write_config("/etc/systemd/sleep.conf.d/90-station-blanche.conf", "[Sleep]\nAllowSuspend=no\nAllowHibernation=no\nAllowSuspendThenHibernate=no\nAllowHybridSleep=no\n")
    write_config("/etc/systemd/logind.conf.d/90-station-blanche.conf", "[Login]\nIdleAction=ignore\nHandleSuspendKey=ignore\nHandleHibernateKey=ignore\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n")
    # Appliquer les réglages du compte dans sa session active si elle existe.
    runtime = Path(f"/run/user/{account.pw_uid}")
    if (runtime / "bus").exists():
        subprocess.run(["runuser", "-u", account.pw_name, "--", "env", f"XDG_RUNTIME_DIR={runtime}", f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus", "/usr/bin/python3", "/usr/local/lib/station-blanche/desktop-session.py"], check=False)
    print(json.dumps({"user": account.pw_name, "display_manager": manager, "installed_desktops": installed_desktops(), "autologin": True, "password": "unchanged"}, ensure_ascii=False))
    print("[OK] Session automatique configurée. Redémarrer Debian pour appliquer tous les réglages, sans interrompre la session actuelle.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, RuntimeError, configparser.Error) as error:
        print(f"[ÉCHEC bureau] {error}", file=sys.stderr)
        sys.exit(1)
