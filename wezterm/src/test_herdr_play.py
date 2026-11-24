"""Check herdr-play serves only allowed files to allowed hosts."""
import importlib.util
import http.client
import json
from pathlib import Path
import stat
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "herdr_play", Path(__file__).with_name("herdr-play.py"))
herdr_play = importlib.util.module_from_spec(spec)
spec.loader.exec_module(herdr_play)


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.rec = root / "rec"
        self.static = root / "static"
        (self.static / "vendor").mkdir(parents=True)
        self.rec.mkdir()
        (self.static / "index.html").write_text("<html></html>", encoding="utf-8")
        (self.static / "vendor" / "p.js").write_text("x", encoding="utf-8")
        (self.rec / "a.cast").write_text('{"version":3}\n', encoding="utf-8")
        (root / "secret.cast").write_text("secret", encoding="utf-8")
        self.patches = [
            patch.object(herdr_play, "REC_DIR", self.rec),
            patch.object(herdr_play, "STATIC_DIR", self.static),
        ]
        for p in self.patches:
            p.start()
        self.server = herdr_play.ThreadingHTTPServer(("127.0.0.1", 0), herdr_play.Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def get(self, path, host=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.putrequest("GET", path, skip_host=True)
        conn.putheader("Host", host or f"127.0.0.1:{self.port}")
        conn.endheaders()
        resp = conn.getresponse()
        body = resp.read()
        conn.close()
        return resp.status, body

    def test_serves_allowed_paths(self):
        self.assertEqual(self.get("/")[0], 200)
        self.assertEqual(self.get("/vendor/p.js")[0], 200)
        self.assertEqual(self.get("/cast/a.cast"), (200, b'{"version":3}\n'))
        status, body = self.get("/api/list")
        self.assertEqual(status, 200)
        self.assertIn(b'"a.cast"', body)

    def test_rejects_traversal_and_other_files(self):
        for path in ("/cast/..%2Fsecret.cast", "/cast/../secret.cast", "/cast/a.txt",
                     "/vendor/..%2Findex.html", "/rec/a.cast"):
            with self.subTest(path=path):
                self.assertEqual(self.get(path)[0], 404)

    def test_rejects_host_other_than_bound_address(self):
        for host in ("evil.example:80", f"localhost:{self.port}", "127.0.0.1"):
            with self.subTest(host=host):
                self.assertEqual(self.get("/cast/a.cast", host=host)[0], 403)

    def post(self, path, body, ctype="application/json", origin=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        headers = {"Content-Type": ctype, "Origin": origin or f"http://127.0.0.1:{self.port}"}
        conn.request("POST", path, body=data, headers=headers)
        resp = conn.getresponse()
        out = resp.read()
        conn.close()
        return resp.status, out

    def test_markers_default_empty_then_roundtrip(self):
        status, body = self.get("/api/markers/a.cast")
        self.assertEqual((status, json.loads(body)), (200, {"next": None, "markers": []}))
        payload = {"next": 4, "markers": [{"t": 12.5, "label": "B"}, {"t": 1, "label": " A "}]}
        status, _ = self.post("/api/markers/a.cast", payload)
        self.assertEqual(status, 200)
        status, body = self.get("/api/markers/a.cast")
        self.assertEqual(status, 200)
        # 依時間排序, label 去頭尾空白, next 原樣保存
        self.assertEqual(json.loads(body), {"next": 4, "markers": [{"t": 1.0, "label": "A"}, {"t": 12.5, "label": "B"}]})
        path = self.rec / "a.markers.json"
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual([p.name for p in self.rec.iterdir() if p.name.startswith(".")], [])

    def test_legacy_array_file_served_as_is(self):
        (self.rec / "a.markers.json").write_text('[{"t": 1, "label": "A"}]', encoding="utf-8")
        self.assertEqual(json.loads(self.get("/api/markers/a.cast")[1]), [{"t": 1, "label": "A"}])

    def test_markers_post_rejections(self):
        ok = [{"t": 1, "label": "A"}]
        wrap = lambda markers, nxt=2: {"next": nxt, "markers": markers}
        cases = {
            "text/plain": (self.post("/api/markers/a.cast", wrap(ok), ctype="text/plain"), 415),
            "foreign origin": (self.post("/api/markers/a.cast", wrap(ok), origin="http://evil.example"), 403),
            "negative t": (self.post("/api/markers/a.cast", wrap([{"t": -1, "label": "A"}])), 400),
            "bool t": (self.post("/api/markers/a.cast", wrap([{"t": True, "label": "A"}])), 400),
            "long label": (self.post("/api/markers/a.cast", wrap([{"t": 1, "label": "x" * 101}])), 400),
            "blank label": (self.post("/api/markers/a.cast", wrap([{"t": 1, "label": "  "}])), 400),
            "extra key": (self.post("/api/markers/a.cast", wrap([{"t": 1, "label": "A", "x": 1}])), 400),
            "markers not array": (self.post("/api/markers/a.cast", wrap({"t": 1, "label": "A"})), 400),
            "bare array (legacy)": (self.post("/api/markers/a.cast", ok), 400),
            "next zero": (self.post("/api/markers/a.cast", wrap(ok, 0)), 400),
            "next bool": (self.post("/api/markers/a.cast", wrap(ok, True)), 400),
            "next float": (self.post("/api/markers/a.cast", wrap(ok, 2.5)), 400),
            "next too big": (self.post("/api/markers/a.cast", wrap(ok, 100001)), 400),
            "missing next": (self.post("/api/markers/a.cast", {"markers": ok}), 400),
            "bad json": (self.post("/api/markers/a.cast", b"{"), 400),
            "missing cast": (self.post("/api/markers/b.cast", wrap(ok)), 404),
            "traversal": (self.post("/api/markers/..%2Fsecret.cast", wrap(ok)), 404),
            "other path": (self.post("/cast/a.cast", wrap(ok)), 404),
        }
        for label, ((status, _), expected) in cases.items():
            with self.subTest(case=label):
                self.assertEqual(status, expected)
        self.assertFalse((self.rec / "a.markers.json").exists())

    def test_markers_file_not_served_as_cast(self):
        (self.rec / "a.markers.json").write_text("[]", encoding="utf-8")
        self.assertEqual(self.get("/cast/a.markers.json")[0], 404)
        self.assertNotIn(b"markers", self.get("/api/list")[1])


class WslIpTests(unittest.TestCase):
    def run_ip(self, stdout):
        result = subprocess.CompletedProcess([], 0, stdout=stdout, stderr="")
        with patch.object(herdr_play.subprocess, "run", return_value=result):
            return herdr_play.wsl_ip()

    def test_parses_eth0_ipv4(self):
        out = "2: eth0    inet 172.21.236.176/20 brd 172.21.239.255 scope global eth0\\       valid_lft forever\n"
        self.assertEqual(self.run_ip(out), "172.21.236.176")

    def test_missing_interface_returns_none(self):
        self.assertIsNone(self.run_ip(""))


if __name__ == "__main__":
    unittest.main()
