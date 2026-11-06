#!/usr/bin/python3
"""Surveillance du rendu Chromium via un pipe privé, sans port de débogage réseau."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, build_opener

KIOSK = "http://127.0.0.1:8080/kiosk"
STOP = False


class Protocol:
    def __init__(self, process):
        self.process, self.serial, self.buffer = process, 0, b""

    def call(self, method, params=None, session=None):
        self.serial += 1
        message = {"id": self.serial, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        self.process.stdin.write(json.dumps(message).encode() + b"\0")
        self.process.stdin.flush()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            while b"\0" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\0", 1)
                reply = json.loads(raw)
                if reply.get("id") == self.serial:
                    if "error" in reply:
                        raise RuntimeError(f"Commande Chromium refusée : {method}")
                    return reply.get("result", {})
            ready, _, _ = select.select([self.process.stdout], [], [], max(0, deadline-time.monotonic()))
            if not ready:
                break
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise RuntimeError("Chromium fermé")
            self.buffer += data
            if len(self.buffer) > 2 * 1024 * 1024:
                raise RuntimeError("Réponse Chromium trop volumineuse")
        raise RuntimeError("Le rendu Chromium ne répond pas")


def station_url(url, origin):
    parsed = urlsplit(url)
    if parsed.username or parsed.password:
        return False
    base = f"{parsed.scheme}://{parsed.netloc}"
    if base == "http://127.0.0.1:8080":
        return parsed.path in ("/kiosk", "/")
    return bool(origin) and base == origin and parsed.path in ("/", "/login", "/auth/login", "/auth/logout", "/kiosk")


def inspect_page(protocol, origin):
    targets = protocol.call("Target.getTargets").get("targetInfos", [])
    pages = [page for page in targets if page.get("type") == "page" and station_url(page.get("url", ""), origin)]
    hidden_target = None
    for page in pages:
        session = protocol.call("Target.attachToTarget", {"targetId": page["targetId"], "flatten": True})["sessionId"]
        try:
            result = protocol.call("Runtime.evaluate", {
                "expression": "JSON.stringify({ready:document.readyState,visible:document.visibilityState==='visible',station:document.title.includes('Station Blanche')&&!!document.querySelector('main')&&!!document.querySelector('#title,#overview,form[action=\"/auth/login\"]'),rendered:!!document.querySelector('main')&&document.querySelector('main').getBoundingClientRect().width>0})",
                "returnByValue": True,
            }, session)
            state = json.loads(result.get("result", {}).get("value", "{}"))
            if state.get("station") and state.get("rendered") and state.get("ready") in ("interactive", "complete"):
                if not state.get("visible"):
                    hidden_target = page["targetId"]
                else:
                    return True, "Page Station Blanche chargée et onglet actif"
        finally:
            protocol.call("Target.detachFromTarget", {"sessionId": session})
    if hidden_target:
        protocol.call("Target.activateTarget", {"targetId": hidden_target})
        return False, "Onglet Station Blanche réactivé"
    return False, "Onglet Station Blanche absent ou page non rendue"


def status(path, state, detail, pid=None):
    data = {"checked_at": int(time.time()), "state": state, "detail": detail, "browser_pid": pid, "desktop": os.environ.get("XDG_CURRENT_DESKTOP", "inconnu")}
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False))
    temporary.chmod(0o600)
    temporary.replace(path)


def terminate(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
    if process:
        for stream in (process.stdin, process.stdout):
            if stream:
                stream.close()


def main():
    global STOP
    if len(sys.argv) != 2:
        raise RuntimeError("Un profil Chromium dédié est requis")
    profile = Path(sys.argv[1])
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", str(profile.parent))) / "station-blanche"
    runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    state_path = runtime / "kiosk-status.json"
    origin_path = Path("/etc/station-blanche/kiosk-origin")
    origin = origin_path.read_text().strip() if origin_path.exists() else ""
    opener = build_opener(ProxyHandler({}))
    process = None

    def stop(_number, _frame):
        global STOP
        STOP = True
    for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(number, stop)
    try:
        while not STOP:
            try:
                with opener.open("http://127.0.0.1:8080/health/live", timeout=3) as response:
                    if response.status != 200:
                        raise RuntimeError("Serveur en préparation")
            except (OSError, RuntimeError):
                status(state_path, "waiting", "Attente du serveur local")
                time.sleep(2)
                continue
            # bash duplique stdin/stdout en FD 3/4 attendus par Chromium. Aucun socket CDP.
            command = ["bash", "-c", 'exec "$@" 3<&0 4>&1 </dev/null >/dev/null', "station-blanche", "chromium",
                       f"--user-data-dir={profile}", "--kiosk", "--no-first-run", "--noerrdialogs",
                       "--disable-background-mode", "--disable-session-crashed-bubble",
                       "--password-store=basic", "--incognito", "--remote-debugging-pipe", KIOSK]
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
            protocol = Protocol(process)
            startup_until = time.monotonic() + 20
            recoveries = 0
            missing_since = None
            status(state_path, "starting", "Démarrage du kiosque", process.pid)
            while not STOP and process.poll() is None:
                try:
                    healthy, detail = inspect_page(protocol, origin)
                except (OSError, ValueError, RuntimeError, KeyError) as error:
                    healthy, detail = False, str(error)
                if healthy:
                    startup_until = 0
                    recoveries = 0
                    missing_since = None
                    status(state_path, "visible", detail, process.pid)
                elif time.monotonic() >= startup_until:
                    missing_since = missing_since or time.monotonic()
                    status(state_path, "recovering", detail, process.pid)
                    if time.monotonic() - missing_since >= 5:
                        if recoveries:
                            break
                        try:
                            protocol.call("Target.createTarget", {"url": KIOSK, "newWindow": True, "windowState": "fullscreen"})
                            recoveries += 1
                            startup_until = time.monotonic() + 20
                            missing_since = None
                        except (OSError, ValueError, RuntimeError):
                            break
                time.sleep(1)
            terminate(process)
            process = None
            if not STOP:
                status(state_path, "restarting", "Chromium fermé ou bloqué ; relance après cinq secondes")
                for _ in range(5):
                    if STOP:
                        break
                    time.sleep(1)
    finally:
        terminate(process)
        status(state_path, "stopped", "Session kiosque arrêtée")


if __name__ == "__main__":
    main()
