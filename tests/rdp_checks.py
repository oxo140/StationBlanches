import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rdp", ROOT / "deploy/host/rdp-config.py")
rdp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rdp)


class RdpTests(unittest.TestCase):
    def test_xorg_repeated_parameters_and_other_settings_are_preserved(self):
        source = "[Globals]\nDefaultWindowManager=startwm.sh\n[Security]\nAllowRootLogin=true\n[Xorg]\nparam=Xorg\nparam=-config\nparam=xrdp/xorg.conf\n"
        changes = rdp.configurations("192.168.156.128")["/etc/xrdp/sesman.ini"]
        result = rdp.patch_ini(source, changes)
        self.assertIn("param=Xorg\nparam=-config\nparam=xrdp/xorg.conf", result)
        self.assertIn("AllowRootLogin=false", result)
        self.assertIn("TerminalServerUsers=station-rdp", result)
        self.assertIn("AlwaysGroupCheck=true", result)
        self.assertEqual(rdp.patch_ini(result, changes), result)

    def test_tls_and_specific_ipv4_listener(self):
        changes = rdp.configurations("192.168.156.128")["/etc/xrdp/xrdp.ini"]
        source = "[Globals]\nsecurity_layer=rdp\nport=3389\n[Channels]\ncliprdr=true\n"
        result = rdp.patch_ini(source, changes)
        self.assertIn("port=tcp://192.168.156.128:3389", result)
        self.assertIn("security_layer=tls", result)
        self.assertIn("cliprdr=true", result)
        self.assertIn("ssl_protocols=TLSv1.2, TLSv1.3", result)
        with self.assertRaises(ValueError):
            rdp.configurations("192.168.1.1\nport=1")

    def test_duplicate_target_values_cannot_override_tls(self):
        result = rdp.patch_ini("[Globals]\nsecurity_layer=rdp\nsecurity_layer=negotiate\n", {"Globals":{"security_layer":"tls"}})
        self.assertEqual(result.count("security_layer=tls"), 2)


if __name__ == "__main__":
    unittest.main()
