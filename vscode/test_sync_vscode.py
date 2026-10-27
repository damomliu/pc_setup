"""以暫存目錄與 mock 驗證同步，不操作本機 VS Code。"""
import contextlib
import importlib.util
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sync_vscode", Path(__file__).with_name("sync_vscode.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.object(sync, "REPO", self.repo))
        self.stack.enter_context(patch.object(sync.Path, "home", return_value=self.root))
        self.stack.enter_context(patch.object(sync.sys, "platform", "darwin"))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        self.stack.enter_context(contextlib.redirect_stderr(io.StringIO()))
        sync.configure_platform()
        (self.repo / "extensions.json").write_text('{}')
        for name, _ in sync.FILES:
            (self.repo / name).write_text('{"a":1}')

    def test_paths(self):
        self.assertEqual(sync.USER, self.root / "Library/Application Support/Code/User")
        self.assertIn(("keybindings.macos.json", "keybindings.json"), sync.FILES)
        with patch.object(sync.sys, "platform", "win32"), patch.dict(sync.os.environ, APPDATA=str(self.root), LOCALAPPDATA=str(self.root)):
            sync.configure_platform()
            self.assertEqual(sync.USER, self.root / "Code/User")
            self.assertIn(("keybindings.json", "keybindings.json"), sync.FILES)
            with patch.object(sync.Path, "is_file", return_value=True):
                self.assertEqual(sync.find_code(), self.root / "Programs/Microsoft VS Code/bin/code.cmd")

    def test_cli_order_and_missing(self):
        system = Path('/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code')
        user = self.root / 'Applications/Visual Studio Code.app/Contents/Resources/app/bin/code'
        for available, expected in [({system, user}, system), ({user}, user), (set(), Path('/bin/code'))]:
            with patch.object(sync.Path, 'is_file', lambda p: p in available), patch.object(sync.shutil, 'which', return_value='/bin/code'):
                self.assertEqual(sync.find_code(), expected)
        with patch.object(sync.Path, 'is_file', return_value=False), patch.object(sync.shutil, 'which', return_value=None):
            self.assertEqual(sync.main(['--check']), 1)
            self.assertFalse(sync.USER.exists())

    def test_push_pull_check_and_jsonc(self):
        with patch.object(sync, 'find_code', return_value=Path('/mock/code')):
            (self.repo / 'keybindings.json').write_text('windows-sentinel')
            with patch.object(sync, 'find_code', side_effect=AssertionError('一般同步不需要 CLI')):
                self.assertEqual(sync.main([]), 0)
            self.assertEqual((sync.USER / 'keybindings.json').read_bytes(), (self.repo / 'keybindings.macos.json').read_bytes())
            (sync.USER / 'keybindings.json').write_text('// comment\n{"a":1,}')
            self.assertEqual(sync.main(['--check']), 0)
            (sync.USER / 'keybindings.json').write_text('{"a":2}')
            self.assertEqual(sync.main(['--check-verbose']), 1)
            with patch.object(sync, 'find_code', side_effect=AssertionError('pull 不需要 CLI')):
                self.assertEqual(sync.main(['--pull']), 0)
            self.assertEqual((self.repo / 'keybindings.json').read_text(), 'windows-sentinel')
            self.assertEqual((self.repo / 'keybindings.macos.json').read_text(), '{"a":2}')
            (self.repo / 'keybindings.macos.json').unlink()
            self.assertEqual(sync.main(['--check']), 1)

    def test_windows_keybindings_mapping(self):
        with patch.object(sync.sys, 'platform', 'win32'), patch.dict(sync.os.environ, APPDATA=str(self.root)):
            sync.configure_platform()
            (self.repo / 'keybindings.json').write_text('{"windows":true}')
            sync.copy_files(False)
            self.assertEqual((sync.USER / 'keybindings.json').read_text(), '{"windows":true}')
            (sync.USER / 'keybindings.json').write_text('{"windows":false}')
            self.assertEqual(sync.check(False), 1)
            sync.copy_files(True)
            self.assertEqual((self.repo / 'keybindings.json').read_text(), '{"windows":false}')
            self.assertEqual(sync.check(False), 0)
            self.assertEqual((self.repo / 'keybindings.macos.json').read_text(), '{"a":1}')

    def test_push_missing_source_does_not_create_destination(self):
        (self.repo / 'mcp.json').unlink()
        self.assertEqual(sync.main([]), 1)
        self.assertFalse(sync.USER.exists())

    def test_profiles_extensions_and_prune(self):
        (self.repo / 'extensions.json').write_text('{"Default":["Publisher.Wanted"],"Python":["python.wanted"]}')
        calls = []
        def run(*args):
            calls.append(args)
            return 'publisher.extra\n' if '--list-extensions' in args else ''
        with patch.object(sync, 'run_code', side_effect=run):
            sync.install_extensions(False)
            self.assertNotIn(('--uninstall-extension', 'publisher.extra'), calls)
            self.assertIn(('--install-extension', 'publisher.wanted'), calls)
            self.assertIn(('--profile', 'Python', '--install-extension', 'python.wanted'), calls)
            calls.clear()
            sync.install_extensions(True)
            self.assertIn(('--uninstall-extension', 'publisher.extra'), calls)
            self.assertIn(('--profile', 'Python', '--uninstall-extension', 'publisher.extra'), calls)

    def test_check_missing_local_file(self):
        sync.copy_files(False)
        (sync.USER / 'settings.json').unlink()
        with patch.object(sync, 'find_code', return_value=Path('/mock/code')):
            self.assertEqual(sync.main(['--check']), 1)

    def test_extension_check_exit_status(self):
        sync.copy_files(False)
        (self.repo / 'extensions.json').write_text('{"Default":["publisher.wanted"]}')
        with patch.object(sync, 'find_code', return_value=Path('/mock/code')):
            with patch.object(sync, 'run_code', return_value='publisher.extra\n'):
                self.assertEqual(sync.main(['--check']), 1)
            with patch.object(sync, 'run_code', return_value='PUBLISHER.WANTED\n'):
                self.assertEqual(sync.main(['--check']), 0)

    def test_unsupported_platform_does_not_write(self):
        with patch.object(sync.sys, 'platform', 'linux'), patch.object(sync.shutil, 'copyfile') as copy:
            self.assertEqual(sync.main([]), 1)
            copy.assert_not_called()
            self.assertFalse(sync.USER.exists())


if __name__ == '__main__':
    unittest.main()
