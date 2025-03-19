import pyudev
import time

# Configuration
log_file = "logdecle.txt"

# Initialisation du contexte et du moniteur
context = pyudev.Context()
monitor = pyudev.Monitor.from_netlink(context)
monitor.filter_by(subsystem='usb')

def log_usb_event(device, action):
    with open(log_file, "a") as log:
        log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {action.upper()}\n")
        for key, value in device.items():
            log.write(f"  {key}: {value}\n")
        log.write("-" * 40 + "\n")
        print(f"{action.upper()} : {device.get('ID_VENDOR', 'Inconnu')} {device.get('ID_MODEL', 'Inconnu')}")

print("Surveillance des périphériques USB en cours...")
for device in iter(monitor.poll, None):
    if device.action in ['add', 'remove']:
        log_usb_event(device, device.action)
