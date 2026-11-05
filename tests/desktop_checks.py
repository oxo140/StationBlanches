import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "deploy/host" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


desktop = load("desktop-config")
supervisor = load("kiosk-supervisor")


class DesktopTests(unittest.TestCase):
    def test_installed_desktops(self):
        self.assertEqual(desktop.installed_desktops(lambda name: name in {"xfce4-session", "startlxqt"}), ["Xfce", "LXQt"])
        self.assertEqual(len(desktop.installed_desktops(lambda _: True)), 8)

    def test_display_managers_and_configuration_preserved(self):
        for manager, text in (("gdm3", "[daemon]\nWaylandEnable=false\n"), ("lightdm", "[Seat:*]\nuser-session=xfce\n"), ("sddm", "[Autologin]\nSession=custom.desktop\n"), ("lxdm", "[base]\ngreeter=/custom\n")):
            with self.subTest(manager=manager):
                writes = {}
                desktop.configure_manager(manager, "william", lambda _: text, lambda path, content: writes.update({path: content}), ["plasma.desktop"])
                self.assertEqual(len(writes), 1)
                content = next(iter(writes.values()))
                self.assertIn("william", content)
                self.assertIn(text.splitlines()[1], content)
                self.assertNotIn("password", content.lower())
        self.assertEqual(desktop.manager_name("/usr/sbin/gdm3\n"), "gdm3")
        self.assertIsNone(desktop.manager_name("/usr/bin/unknown"))

    def test_sddm_chooses_installed_session(self):
        writes = {}
        desktop.configure_manager("sddm", "william", lambda _: "", lambda path, text: writes.update({path:text}), ["xfce.desktop", "plasma.desktop"])
        self.assertIn("Session=plasma.desktop", writes["/etc/sddm.conf"])
        with self.assertRaises(RuntimeError):
            desktop.configure_manager(None, "william", lambda _: "", lambda *_: None, [])


class FakeProtocol:
    def __init__(self, pages, states):
        self.pages, self.states, self.calls = pages, states, []

    def call(self, method, params=None, session=None):
        self.calls.append((method, params, session))
        if method == "Target.getTargets":
            return {"targetInfos":self.pages}
        if method == "Target.attachToTarget":
            return {"sessionId":params["targetId"]}
        if method == "Runtime.evaluate":
            return {"result":{"value":json.dumps(self.states[session])}}
        return {}


class KioskTests(unittest.TestCase):
    origin = "https://192.0.2.1"

    @unittest.skipUnless(os.name == "posix", "Les pipes Chromium FD 3/4 nécessitent Linux")
    def test_private_pipe_protocol(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / "chromium.py"
            script.write_text('''import os,json
buffer=b""
while True:
    data=os.read(3,65536)
    if not data: break
    buffer+=data
    while b"\\0" in buffer:
        raw,buffer=buffer.split(b"\\0",1)
        request=json.loads(raw)
        os.write(4,json.dumps({"id":request["id"],"result":{"method":request["method"]}}).encode()+b"\\0")
''')
            process = subprocess.Popen(["bash", "-c", 'exec "$@" 3<&0 4>&1 </dev/null >/dev/null', "test-pipe", sys.executable, str(script)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)
            try:
                protocol = supervisor.Protocol(process)
                self.assertEqual(protocol.call("Target.getTargets"), {"method":"Target.getTargets"})
                self.assertEqual(protocol.call("Runtime.evaluate", {}, "session"), {"method":"Runtime.evaluate"})
            finally:
                supervisor.terminate(process)

    def test_only_station_urls_are_accepted(self):
        for url in (supervisor.KIOSK, self.origin+"/login", self.origin+"/"):
            self.assertTrue(supervisor.station_url(url, self.origin))
        for url in ("https://192.0.2.1.evil.invalid/", "https://user:password@192.0.2.1/", "chrome://crash", "https://192.0.2.1/other"):
            self.assertFalse(supervisor.station_url(url, self.origin))

    def test_visible_supervision_is_not_replaced_by_hidden_kiosk(self):
        pages = [{"targetId":"kiosk", "type":"page", "url":supervisor.KIOSK}, {"targetId":"admin", "type":"page", "url":self.origin+"/"}]
        states = {name:{"ready":"complete", "station":True, "rendered":True, "visible":name=="admin"} for name in ("kiosk", "admin")}
        protocol = FakeProtocol(pages, states)
        self.assertTrue(supervisor.inspect_page(protocol, self.origin)[0])
        self.assertNotIn("Target.activateTarget", [call[0] for call in protocol.calls])

    def test_hidden_page_is_reactivated_and_error_page_is_rejected(self):
        page = {"targetId":"kiosk", "type":"page", "url":supervisor.KIOSK}
        protocol = FakeProtocol([page], {"kiosk":{"ready":"complete", "station":True, "rendered":True, "visible":False}})
        self.assertFalse(supervisor.inspect_page(protocol, self.origin)[0])
        self.assertIn("Target.activateTarget", [call[0] for call in protocol.calls])
        protocol.states["kiosk"]["station"] = False
        self.assertFalse(supervisor.inspect_page(protocol, self.origin)[0])
        self.assertFalse(supervisor.inspect_page(FakeProtocol([], {}), self.origin)[0])


if __name__ == "__main__":
    unittest.main()
