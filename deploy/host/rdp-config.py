#!/usr/bin/python3
"""Configuration XRDP : préserver les lignes param= répétées de Xorg."""
import importlib.util
import ipaddress
import os
from pathlib import Path
import re
import sys


def patch_ini(text, changes):
    wanted = {section.lower(): {key.lower(): (key, str(value)) for key, value in values.items()} for section, values in changes.items()}
    remaining = {section: values.copy() for section, values in wanted.items()}
    output, section = [], ""

    def finish():
        output.extend(f"{key}={value}" for key, value in remaining.get(section, {}).values())
        remaining.pop(section, None)

    for line in text.splitlines():
        match = re.match(r"\s*\[([^]]+)\]", line)
        if match:
            finish()
            section = match[1].lower()
            output.append(line)
            continue
        key = line.split("=", 1)[0].strip().lower() if "=" in line else ""
        if section in wanted and key in wanted[section] and not line.lstrip().startswith((";", "#")):
            original, value = wanted[section][key]
            remaining.get(section, {}).pop(key, None)
            output.append(f"{original}={value}")
        else:
            output.append(line)
    finish()
    for section, values in remaining.items():
        output.append(f"\n[{section}]")
        output.extend(f"{key}={value}" for key, value in values.values())
    return "\n".join(output) + "\n"


def configurations(ip):
    ipaddress.IPv4Address(ip)
    return {
        "/etc/xrdp/xrdp.ini": {
            "Globals": {"port": f"tcp://{ip}:3389", "security_layer": "tls", "ssl_protocols": "TLSv1.2, TLSv1.3", "crypt_level": "high", "autorun": "Xorg"},
        },
        "/etc/xrdp/sesman.ini": {
            "Globals": {"EnableUserWindowManager": "false", "DefaultWindowManager": "/usr/local/lib/station-blanche/rdp-session.sh"},
            "Security": {"AllowRootLogin": "false", "MaxLoginRetry": "3", "TerminalServerUsers": "station-rdp", "AlwaysGroupCheck": "true"},
            "Sessions": {"MaxSessions": "2", "KillDisconnected": "true", "DisconnectedTimeLimit": "300", "IdleTimeLimit": "0"},
            "SessionVariables": {"SB_RDP_SESSION": "1"},
        },
    }


def main():
    if os.geteuid() != 0 or len(sys.argv) != 2:
        raise RuntimeError("Utilisation : sudo python3 rdp-config.py IP_STATION")
    spec = importlib.util.spec_from_file_location("desktop", Path(__file__).with_name("desktop-config.py"))
    desktop = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(desktop)
    for path, changes in configurations(sys.argv[1]).items():
        source = Path(path)
        if not source.is_file():
            raise RuntimeError(f"Configuration XRDP absente : {path}")
        desktop.write_config(path, patch_ini(source.read_text(), changes))


if __name__ == "__main__":
    main()
