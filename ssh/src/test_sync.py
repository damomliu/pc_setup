"""以隔離目錄驗證同步，不存取使用者的 SSH 設定。"""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("ssh_sync", Path(__file__).parents[1] / "sync.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.repo = sync.LocalStore(root / "repo")
        self.win = sync.LocalStore(root / "win")
        self.wsl = sync.LocalStore(root / "wsl")
        self.targets = [("win", self.win), ("wsl", self.wsl)]
        for store in (self.repo, self.win, self.wsl):
            store.root.mkdir()
        for kind, _ in self.targets:
            for name in sync.FILES:
                self.repo.write(sync.repo_name(name, kind), f"# {sync.repo_name(name, kind)}\n".encode())

    def run_sync(self, mode, targets=None):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return sync.sync(mode, self.repo, self.targets if targets is None else targets)

    def test_platform_mapping_round_trip_and_idempotence(self):
        self.assertEqual(self.run_sync("push"), 0)
        self.assertNotEqual(self.win.read(sync.FILES)["with-identity.conf"], self.wsl.read(sync.FILES)["with-identity.conf"])
        self.assertEqual(self.run_sync("check"), 0)
        with patch.object(sync, "atomic_write", side_effect=AssertionError("unexpected write")):
            self.assertEqual(self.run_sync("push"), 0)
        for store in (self.win, self.wsl):
            store.write("config", b"# updated shared\n")
        self.assertEqual(self.run_sync("pull"), 0)
        self.assertEqual(self.repo.read(("config",))["config"], b"# updated shared\n")

    def test_check_is_read_only_and_ignores_crlf(self):
        self.assertEqual(self.run_sync("check"), 1)
        self.assertFalse((self.win.root / "config").exists())
        self.run_sync("push")
        (self.win.root / "config").write_bytes(b"# config\r\n")
        with patch.object(sync, "atomic_write", side_effect=AssertionError("unexpected write")):
            self.assertEqual(self.run_sync("check"), 0)
            self.assertEqual(self.run_sync("push"), 0)

    def test_shared_pull_conflict_prevents_all_writes(self):
        self.run_sync("push")
        before = self.repo.read(tuple(path.name for path in self.repo.root.iterdir()))
        self.win.write("with-identity.conf", b"changed identity\n")
        self.wsl.write("ipc.conf", b"conflict\n")
        with self.assertRaisesRegex(OSError, "共用檔來源衝突"):
            self.run_sync("pull")
        self.assertEqual(before, self.repo.read(tuple(before)))
        self.assertEqual(self.run_sync("pull", [("wsl", self.wsl)]), 0)
        self.assertEqual(self.repo.read(("ipc.conf",))["ipc.conf"], b"conflict\n")

    def test_missing_source_prevents_all_writes(self):
        (self.repo.root / "with-identity.wsl.conf").unlink()
        with self.assertRaisesRegex(OSError, "來源缺失"):
            self.run_sync("push")
        self.assertEqual(list(self.win.root.iterdir()), [])

    def test_only_managed_files_and_single_target(self):
        untouched = self.win.root / "shared.conf"
        untouched.write_bytes(b"untouched")
        self.run_sync("push", [("win", self.win)])
        self.assertEqual(untouched.read_bytes(), b"untouched")
        self.assertEqual(list(self.wsl.root.iterdir()), [])

    def test_write_failure_reports_remaining(self):
        output = io.StringIO()
        with patch.object(self.win, "write", side_effect=OSError("denied")):
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(output):
                with self.assertRaises(OSError):
                    sync.sync("push", self.repo, self.targets)
        self.assertIn("已完成 0", output.getvalue())
        self.assertIn(self.wsl.path("with-identity.conf"), output.getvalue())

    def test_read_error_prevents_all_writes(self):
        with patch.object(self.wsl, "read", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                self.run_sync("push")
        self.assertEqual(list(self.win.root.iterdir()), [])

    def test_modes_and_target_options_are_mutually_exclusive(self):
        for flags in ([], ["--check", "--push"], ["--pull", "--win-only", "--wsl-only"], ["--chec"]):
            with self.subTest(flags=flags), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    sync.parse_args(flags)
                self.assertEqual(result.exception.code, 2)

    def test_wsl_rejects_cross_target_options(self):
        with patch.object(sys, "platform", "linux"), patch.dict(os.environ, {"WSL_DISTRO_NAME": "Test"}):
            self.assertTrue(sync.parse_args(["--check"]).local_wsl)
            for flag in (["--win-only"], ["--wsl-only"], ["--distro", "Test"]):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    sync.parse_args(["--check", *flag])

    def test_windows_cli_selection_and_error_exit(self):
        for flags, expected in (([], ["win", "wsl"]), (["--win-only"], ["win"]),
                                (["--wsl-only", "--distro", "Other"], ["wsl"])):
            with patch.object(sys, "platform", "win32"), patch.object(sync, "WslStore") as remote:
                with patch.object(sync, "sync", return_value=1) as operation:
                    with contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(sync.main(["--check", *flags]), 1)
                    self.assertEqual([kind for kind, _ in operation.call_args.args[2]], expected)
                if "wsl" in expected:
                    remote.assert_called_once_with("Other" if "--distro" in flags else "Ubuntu-24.04")
                else:
                    remote.assert_not_called()
        with patch.object(sys, "platform", "win32"), patch.object(sync, "WslStore", side_effect=OSError("offline")):
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(sync.main(["--check"]), 2)

    @unittest.skipUnless(os.name == "nt", "Windows ACL")
    def test_windows_existing_acl_is_preserved(self):
        import ctypes
        file = self.win.root / "config"
        self.win.write("config", b"before")
        account = subprocess.run(["whoami"], capture_output=True, text=True, check=True).stdout.strip()
        subprocess.run(["icacls", str(file), "/inheritance:r", "/grant:r", account + ":F"],
                       capture_output=True, check=True)

        def dacl():
            library = ctypes.WinDLL("advapi32", use_last_error=True)
            get_security = library.GetFileSecurityW
            get_security.argtypes = (ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_void_p,
                                     ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint32))
            required = ctypes.c_uint32()
            get_security(str(file), 4, None, 0, ctypes.byref(required))
            buffer = ctypes.create_string_buffer(required.value)
            if not get_security(str(file), 4, buffer, required.value, ctypes.byref(required)):
                raise ctypes.WinError(ctypes.get_last_error())
            return buffer.raw

        before = dacl()
        self.win.write("config", b"after")
        self.assertEqual(dacl(), before)
        self.assertEqual(file.read_bytes(), b"after")

    @unittest.skipUnless(os.name == "posix", "Linux mode bits")
    def test_linux_permissions_and_symlink_refusal(self):
        file = self.win.root / "config"
        self.win.write("config", b"new")
        self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)
        file.chmod(0o640)
        self.win.write("config", b"updated")
        self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o640)
        link = self.win.root / "ipc.conf"
        link.symlink_to(file)
        with self.assertRaises(OSError):
            self.win.write("ipc.conf", b"bad")
        self.assertEqual(file.read_bytes(), b"updated")

    def test_remote_helper_runs_without_changing_real_home(self):
        """用隔離 HOME 執行真正的 remote helper，驗證 stdin/stdout protocol。"""
        if os.name != "posix":
            self.skipTest("WSL helper 的 Linux HOME 行為")
        real_run = subprocess.run

        def isolated_run(command, **kwargs):
            self.assertEqual(command[:5], ["wsl.exe", "-d", "Test", "--", "python3"])
            return real_run([sys.executable, *command[5:]],
                            env={**os.environ, "HOME": str(self.wsl.root)}, **kwargs)

        with patch.object(sync.subprocess, "run", side_effect=isolated_run):
            remote = sync.WslStore("Test")
            self.assertEqual(remote.read(sync.FILES), dict.fromkeys(sync.FILES))
            remote.write("config", b"test\r\n")
            self.assertEqual(remote.read(sync.FILES)["config"], b"test\n")
            self.assertEqual(stat.S_IMODE((self.wsl.root / ".ssh/config").stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
