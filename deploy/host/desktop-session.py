#!/usr/bin/python3
"""Réglages du bureau exécutés avec les droits du compte kiosque."""
import configparser
import io
import os
from pathlib import Path
import shutil
import subprocess


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=8, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def ini(path, changes):
    path = Path(path)
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str
    if path.exists():
        parser.read(path)
        backup = Path.home() / ".config/station-blanche/desktop-backups" / path.name
        if not backup.exists():
            backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copy2(path, backup)
    for section, values in changes.items():
        if not parser.has_section(section):
            parser.add_section(section)
        for key, value in values.items():
            parser.set(section, key, str(value))
    output = io.StringIO()
    parser.write(output, space_around_delimiters=False)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(output.getvalue())


def main():
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    # Ne modifier que les schémas et clés réellement présents sur ce bureau.
    result = run(["gsettings", "list-schemas"])
    schemas = set(result.stdout.splitlines()) if result and result.returncode == 0 else set()
    settings = {
        "org.gnome.desktop.session": {"idle-delay": "uint32 0"},
        "org.gnome.desktop.screensaver": {"lock-enabled": "false", "idle-activation-enabled": "false"},
        "org.gnome.settings-daemon.plugins.power": {"sleep-inactive-ac-type": "'nothing'", "sleep-inactive-battery-type": "'nothing'", "idle-dim": "false"},
        "org.cinnamon.desktop.session": {"idle-delay": "uint32 0"},
        "org.cinnamon.desktop.screensaver": {"lock-enabled": "false", "idle-activation-enabled": "false"},
        "org.cinnamon.settings-daemon.plugins.power": {"sleep-inactive-ac-type": "'nothing'", "sleep-inactive-battery-type": "'nothing'", "sleep-display-ac": "0", "sleep-display-battery": "0", "idle-dim-ac": "false", "idle-dim-battery": "false"},
        "org.mate.session": {"idle-delay": "0"},
        "org.mate.screensaver": {"lock-enabled": "false", "idle-activation-enabled": "false"},
        "org.mate.power-manager": {"sleep-computer-ac": "0", "sleep-computer-battery": "0", "sleep-display-ac": "0", "sleep-display-battery": "0", "lock-suspend": "false", "lock-hibernate": "false"},
    }
    failures = []
    for schema, values in settings.items():
        if schema not in schemas:
            continue
        keys = run(["gsettings", "list-keys", schema])
        existing = keys.stdout.splitlines() if keys else []
        for key, value in values.items():
            if key in existing:
                applied = run(["gsettings", "set", schema, key, value])
                if not applied or applied.returncode:
                    failures.append(f"{schema}/{key}")
    if shutil.which("xfconf-query"):
        channels = {
            "xfce4-power-manager": {
                "dpms-enabled": ("bool", "false"), "lock-screen-suspend-hibernate": ("bool", "false"),
                "blank-on-ac": ("int", "0"), "blank-on-battery": ("int", "0"),
                "inactivity-on-ac": ("uint", "0"), "inactivity-on-battery": ("uint", "0"),
            },
            "xfce4-screensaver": {"saver/enabled": ("bool", "false"), "lock/enabled": ("bool", "false")},
        }
        for channel, values in channels.items():
            for key, (kind, value) in values.items():
                path = f"/xfce4-power-manager/{key}" if channel == "xfce4-power-manager" else f"/{key}"
                args = ["xfconf-query", "-c", channel, "-p", path, "-s", value]
                applied = run(args)
                if not applied or applied.returncode:
                    applied = run(args + ["--create", "--type", kind])
                if not applied or applied.returncode:
                    failures.append(f"{channel}{path}")
    if shutil.which("startplasma-wayland") or shutil.which("startplasma-x11"):
        ini(config / "kscreenlockerrc", {"Daemon": {"Autolock": "false", "LockOnResume": "false", "Timeout": "0"}})
        ini(config / "powerdevilrc", {f"{profile}][{section}": values for profile in ("AC", "Battery", "LowBattery") for section, values in {
            "SuspendAndShutdown": {"AutoSuspendAction": "0", "AutoSuspendIdleTimeoutSec": "0", "LidAction": "0"},
            "Display": {"TurnOffDisplayWhenIdle": "false", "DimDisplayWhenIdle": "false", "TurnOffDisplayIdleTimeoutSec": "-1", "DimDisplayIdleTimeoutSec": "-1", "LockBeforeTurnOffDisplay": "false"},
        }.items()})
    if shutil.which("startlxqt"):
        ini(config / "lxqt/lxqt-powermanagement.conf", {"General": {"enableIdlenessWatcher": "false", "enableLidWatcher": "false"}})
    if shutil.which("lxsession"):
        path = config / "lxsession/LXDE/autostart"
        original = path if path.exists() else Path("/etc/xdg/lxsession/LXDE/autostart")
        if original.exists():
            lines = original.read_text().splitlines()
            filtered = [line for line in lines if not line.lstrip("@ ").startswith(("xscreensaver", "light-locker"))]
            if filtered != lines:
                backup = config / "station-blanche/desktop-backups/lxde-autostart"
                if not backup.exists():
                    backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                    backup.write_text("\n".join(lines) + "\n")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("\n".join(filtered) + "\n")
    # Les verrous externes LXDE/LXQt/Xfce ne doivent pas se lancer automatiquement.
    for name in ("light-locker", "xscreensaver"):
        path = config / f"autostart/{name}.desktop"
        ini(path, {"Desktop Entry": {"Type": "Application", "Name": name, "Hidden": "true"}})
    if os.environ.get("DISPLAY"):
        for args in (["xset", "s", "off"], ["xset", "s", "noblank"], ["xset", "-dpms"]):
            run(args)
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", os.environ.get("DESKTOP_SESSION", "détection par composants installés"))
    print(f"[BUREAU] {desktop} : réglages anti-veille appliqués au compte courant.")
    if failures:
        print("[À VÉRIFIER] Réglages refusés : " + ", ".join(failures))


if __name__ == "__main__":
    main()
