"""sync.py / sync_claude.py / sync_codex.py 的隔離測試（標準函式庫 unittest，無第三方依賴）。

每個情境在暫存目錄建立 repo、假的 Windows home、假的 WSL home，並把同步器複製進暫存 repo。
CLI 整合情境以 subprocess 執行並使用隱藏參數 --test-win-home / --test-wsl-root（僅 Windows 執行）；
平台模式以 in-process main(argv) 搭配 mock.patch 驗證。不碰真實 home、不呼叫真實 WSL、不執行真實同步；
"real sources" 情境只把 repo 內的來源檔複製到暫存環境。

用法：python ai-agent/test_sync.py（或 python -m unittest discover -s ai-agent -p "test_*.py"）
"""
import sys

sys.dont_write_bytecode = True

import contextlib  # noqa: E402
import hashlib  # noqa: E402
import io  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import tempfile  # noqa: E402
import unittest  # noqa: E402
import uuid  # noqa: E402
from pathlib import Path  # noqa: E402
from unittest import mock  # noqa: E402

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import sync  # noqa: E402
import sync_claude  # noqa: E402
import sync_codex  # noqa: E402
import sync_common as c  # noqa: E402

SCRIPTS = ("sync.py", "sync_claude.py", "sync_codex.py", "sync_common.py")
ON_WINDOWS = os.name == "nt"
WSL_FAKE_HOME = "/home/fake"

FIXTURES = {
    "claude-settings.json": '{"permissions":{"allow":["A","B"]},"model":"sonnet","effortLevel":"medium","modelSettings":{"m1":{"effortLevel":"medium"}},"theme":"dark","count":1,"nested":{"ok":"visible-repo"},"env":{"X":"REPOENV"},"myToken":"REPOTOK"}',
    "claude-settings.wsl.json": '{"permissions":{"allow":["B","C"]},"statusLine":{"command":"wsl-status"}}',
    "claude-settings.macos.json": '{"permissions":{"allow":["B","D"]},"statusLine":{"command":"mac-status"}}',
    "claude-keybindings.json": '{"bindings":[{"action":"x"}]}',
    "claude-statusline.py": "print(1)\n",
    "CLAUDE.md": "# rules\n",
    "claude-pstack-models.md": "# pstack\n\nfeature, refactoring: sonnet\n\ndefault effort: session\nsession hook: off\n",
    "AGENTS.md": "# rules\n\n- be nice\n",
    "codex-config.toml": 'model = "gpt-x"\nmodel_reasoning_effort = "medium"\napproval_policy = "on-request"\n\n[tui]\nstatus_line = ["a", "b"]\n\n[tui.keymap.editor]\ninsert_newline = ["ctrl-enter"]\n\n[tools.env]\nA = "REPOTOML"\n',
}


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

def w(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


def rd(path):
    return Path(path).read_bytes().decode("utf-8")


def rj(path):
    return json.loads(rd(path))


def edit_json(path, edit):
    o = rj(path)
    edit(o)
    w(path, json.dumps(o, indent=2) + "\n")


def snap(root):
    """路徑、大小、修改時間、內容雜湊；用來驗證檔案完全沒被動過。"""
    out = []
    for d, _, files in os.walk(root):
        for f in sorted(files):
            p = Path(d) / f
            st = p.stat()
            out.append((str(p), st.st_size, st.st_mtime_ns, hashlib.sha256(p.read_bytes()).hexdigest()))
    return sorted(out)


def write_fake_wsl(bindir, fail):
    """假的 wsl：被呼叫就留下標記；fail 時結束碼 1，否則輸出假的 HOME。"""
    bindir = Path(bindir)
    if ON_WINDOWS:
        w(bindir / "wsl.cmd", '@echo called>"%~dp0called.txt"\r\n' + ("@exit /b 1\r\n" if fail else f"@echo {WSL_FAKE_HOME}\r\n"))
    else:
        p = bindir / "wsl"
        w(p, '#!/bin/sh\necho called > "$(dirname "$0")/called.txt"\n' + ("exit 1\n" if fail else f"echo {WSL_FAKE_HOME}\n"))
        p.chmod(0o755)


class Env:
    def __init__(self, real_sources=False):
        self.root = Path(tempfile.mkdtemp(prefix="sync-test-")) / uuid.uuid4().hex[:8]
        self.repo, self.win, self.wsl, self.bin = (self.root / n for n in ("repo", "win", "wsl", "bin"))
        for d in (self.repo, self.win, self.wsl, self.bin):
            d.mkdir(parents=True)
        for s in SCRIPTS:
            shutil.copy(HERE / s, self.repo)
        for name, text in FIXTURES.items():
            if real_sources:
                shutil.copy(HERE / name, self.repo)
            else:
                w(self.repo / name, text)
        write_fake_wsl(self.bin, fail=True)

    def cleanup(self):
        shutil.rmtree(self.root.parent, ignore_errors=True)

    def wsl_called(self):
        return (self.bin / "called.txt").exists()

    def hashes(self):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(self.repo.iterdir()) if p.is_file()}


class Result:
    def __init__(self, out, code):
        self.out, self.code = out, code


def run(e, script, args=(), test_paths=True):
    """以 CLI 執行；預設附上成對的測試路徑。PATH 前面放假 wsl，偵測是否被呼叫。"""
    cmd = [sys.executable, "-B", str(e.repo / script), *args]
    if test_paths:
        cmd += ["--test-win-home", str(e.win), "--test-wsl-root", str(e.wsl)]
    env = dict(os.environ, PATH=str(e.bin) + os.pathsep + os.environ.get("PATH", ""), PYTHONIOENCODING="cp1252")
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, stdin=subprocess.DEVNULL)
    return Result(p.stdout.decode("utf-8"), p.returncode)


def inproc(e, module, argv, plat, local=None):
    """in-process 執行 main(argv)；mock 單一平台偵測函式與 home 解析，不碰真實設定。"""
    out, err = io.StringIO(), io.StringIO()
    patches = [mock.patch.object(c, "detect_platform", return_value=plat)]
    if local is not None:
        patches.append(mock.patch.object(c, "local_home", return_value=Path(local)))
    with contextlib.ExitStack() as st:
        for p in patches:
            st.enter_context(p)
        st.enter_context(contextlib.redirect_stdout(out))
        st.enter_context(contextlib.redirect_stderr(err))
        rc = module.main(list(argv), e.repo)
    return Result(out.getvalue() + err.getvalue(), rc)


def forbid_wsl():
    """任何 WSL 查詢都視為失敗。"""
    return mock.patch.object(c, "query_wsl_home", side_effect=AssertionError("不應查詢 WSL"))


class EnvTestCase(unittest.TestCase):
    def env(self, **kw):
        e = Env(**kw)
        self.addCleanup(e.cleanup)
        return e

    def pushed(self):
        e = self.env()
        r = run(e, "sync.py")
        self.assertEqual(r.code, 0, f"初次推送應成功：{r.out}")
        return e


# ---------------------------------------------------------------------------
# 語法與純函式
# ---------------------------------------------------------------------------

class SyntaxAndUnits(unittest.TestCase):
    def test_syntax(self):
        for f in (*SCRIPTS, "test_sync.py"):
            compile((HERE / f).read_text(encoding="utf-8"), f, "exec")

    def test_canonical_json_distinguishes_types(self):
        self.assertNotEqual(c.canonical({"a": True}), c.canonical({"a": 1}))
        self.assertNotEqual(c.canonical({"a": 1}), c.canonical({"a": 1.0}))
        self.assertEqual(c.canonical({"b": 1, "a": 2}), c.canonical({"a": 2, "b": 1}))

    def test_merge_settings_permissions_union_case_insensitive(self):
        base = {"permissions": {"allow": ["A", "b"], "x": 1}, "other": {"allow": ["A"]}}
        over = {"permissions": {"allow": ["B", "C", "C"], "x": 2}, "other": {"allow": ["Z"]}}
        out = sync_claude.merge_settings(base, over)
        self.assertEqual(out["permissions"]["allow"], ["A", "b", "C", "C"])  # 不順帶改變原本的去重規則
        self.assertEqual(out["permissions"]["x"], 2)
        self.assertEqual(out["other"]["allow"], ["Z"])  # 僅頂層 permissions 取聯集

    def test_detect_platform(self):
        cases = [
            ("win32", {}, "6.1", "windows"),
            ("darwin", {}, "23.0", "macos"),
            ("linux", {"WSL_DISTRO_NAME": "Ubuntu"}, "6.6.0", "wsl"),
            ("linux", {}, "5.15.153.1-Microsoft-standard-WSL2", "wsl"),
            ("linux", {}, "6.8.0-generic", "linux"),
            ("freebsd14", {}, "14.0", "other"),
        ]
        for plat, envvars, release, want in cases:
            with self.subTest(plat=plat, release=release):
                with mock.patch.object(sys, "platform", plat), \
                        mock.patch.dict(os.environ, envvars), \
                        mock.patch("platform.release", return_value=release):
                    if "WSL_DISTRO_NAME" not in envvars:
                        os.environ.pop("WSL_DISTRO_NAME", None)
                    self.assertEqual(c.detect_platform(), want)


# ---------------------------------------------------------------------------
# CLI 整合（subprocess，Windows 雙環境）
# ---------------------------------------------------------------------------

@unittest.skipUnless(ON_WINDOWS, "CLI 整合情境以 Windows 雙環境為準")
class CliTests(EnvTestCase):
    def test_first_create(self):
        e = self.pushed()
        for h in (e.win, e.wsl):
            self.assertEqual(rd(h / ".claude/CLAUDE.md"), rd(e.repo / "CLAUDE.md"))
            self.assertNotRegex(rd(h / ".claude/CLAUDE.md"), r"C:|/home/")
            self.assertEqual(rd(h / ".claude/pstack-models.md"), rd(e.repo / "claude-pstack-models.md"))
            self.assertEqual(rd(h / ".codex/AGENTS.md"), rd(e.repo / "AGENTS.md"))
            self.assertNotEqual(rd(h / ".codex/AGENTS.md"), rd(h / ".claude/CLAUDE.md"))
            self.assertFalse((h / ".codex/pstack-models.md").exists())
            s = rj(h / ".claude/settings.json")
            self.assertNotIn("model", s)
            self.assertNotIn("effortLevel", s)
            self.assertEqual(s["modelSettings"]["m1"]["effortLevel"], "medium")
            cfg = rd(h / ".codex/config.toml")
            self.assertNotRegex(cfg, r"(?m)^model")
            self.assertIn('approval_policy = "on-request"', cfg)
        wsl = rj(e.wsl / ".claude/settings.json")
        self.assertEqual(wsl["statusLine"]["command"], "wsl-status")
        self.assertEqual(wsl["permissions"]["allow"], ["A", "B", "C"])
        self.assertNotIn("statusLine", rj(e.win / ".claude/settings.json"))
        self.assertFalse((e.repo / "codex-pstack-models.md").exists())
        self.assertFalse(e.wsl_called())

    def test_codex_does_not_manage_pstack(self):
        e = self.pushed()
        for h in (e.win, e.wsl):
            w(h / ".codex/pstack-models.md", "LOCAL-PSTACK\n")
        before = snap(e.root)
        r = run(e, "sync_codex.py", ["--check-verbose"])
        self.assertEqual(r.code, 0)
        self.assertNotRegex(r.out, r"pstack-models|LOCAL-PSTACK|differs")
        self.assertEqual(snap(e.root), before)
        w(e.repo / "AGENTS.md", "# plain rules\n")
        r = run(e, "sync_codex.py", ["--force"])
        self.assertEqual(r.code, 0, r.out)
        for h in (e.win, e.wsl):
            self.assertEqual(rd(h / ".codex/AGENTS.md"), "# plain rules\n")
            self.assertEqual(rd(h / ".codex/pstack-models.md"), "LOCAL-PSTACK\n")

    def test_string_case_is_significant(self):
        e = self.pushed()
        edit_json(e.repo / "claude-settings.json", lambda o: o.update(name="Value"))
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(name="value"))
        r = run(e, "sync_claude.py", ["--check-verbose"])
        self.assertIn("differs", r.out)
        self.assertIn('name: "value" → "Value"', r.out)
        w(e.repo / "codex-config.toml", rd(e.repo / "codex-config.toml").replace('"on-request"', '"CaseValue"'))
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace('"on-request"', '"casevalue"'))
        r = run(e, "sync_codex.py", ["--check-verbose"])
        self.assertIn("differs", r.out)
        self.assertIn('approval_policy: "casevalue" → "CaseValue"', r.out)
        # section 名稱區分大小寫：[TUI] 不是 [tui]
        w(e.win / ".codex/config.toml", rd(e.repo / "codex-config.toml").replace("[tui]", "[TUI]"))
        r = run(e, "sync_codex.py", ["--check-verbose"])
        self.assertIn("status_line: (missing)", r.out)

    def test_codex_pull(self):
        e = self.pushed()
        for src, flag in ((e.win, "--pull-win"), (e.wsl, "--pull-wsl")):
            w(src / ".codex/pstack-models.md", "LOCAL-PSTACK\n")
            w(src / ".codex/AGENTS.md", f"# {flag} rules\n")
            w(src / ".codex/config.toml", rd(src / ".codex/config.toml").replace("on-request", "never"))
            r = run(e, "sync_codex.py", [flag])
            self.assertEqual(r.code, 0, r.out)
            self.assertEqual(rd(e.repo / "AGENTS.md"), f"# {flag} rules\n")
            self.assertIn('approval_policy = "never"', rd(e.repo / "codex-config.toml"))
            self.assertEqual(rd(src / ".codex/pstack-models.md"), "LOCAL-PSTACK\n")
        w(e.win / ".codex/AGENTS.md", "# should not be pulled\n")
        w(e.repo / "codex-config.toml", "invalid TOML\n")
        before = snap(e.repo)
        r = run(e, "sync_codex.py", ["--pull-win"])
        self.assertNotEqual(r.code, 0)
        self.assertEqual(snap(e.repo), before, "設定解析失敗時也不寫入指引")

    def test_codex_pull_warns_on_missing_key(self):
        e = self.pushed()
        w(e.win / ".codex/config.toml", 'approval_policy = "never"\n')
        r = run(e, "sync_codex.py", ["--pull-win"])
        self.assertEqual(r.code, 0, r.out)
        self.assertIn("沒有 tui.status_line，略過", r.out)
        t = rd(e.repo / "codex-config.toml")
        self.assertIn('approval_policy = "never"', t)
        self.assertIn('status_line = ["a", "b"]', t)

    def test_pull_with_different_guidance_does_not_abort(self):
        e = self.pushed()
        self.assertEqual(run(e, "sync.py", ["--pull-win"]).code, 0)
        self.assertEqual(run(e, "sync.py", ["--pull-wsl"]).code, 0)

    def test_only_ignored_fields_differ(self):
        e = self.pushed()
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(model="LOCALMODEL", effortLevel="high"))
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(model="WSLMODEL"))
        for h in (e.win, e.wsl):
            w(h / ".codex/config.toml", 'model = "local"\nmodel_reasoning_effort = "high"\n' + rd(h / ".codex/config.toml"))
        before = snap(e.root)
        for mode in (["--check"], ["--check-verbose"], []):
            r = run(e, "sync.py", mode)
            self.assertEqual(r.code, 0, r.out)
            self.assertNotRegex(r.out, r"differs|missing|update")
            self.assertNotRegex(r.out, r"LOCALMODEL|WSLMODEL|effortLevel")
        self.assertEqual(snap(e.root), before, "沒有任何檔案被改寫")

    def test_force_keeps_ignored_fields(self):
        e = self.pushed()
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(theme="light", model="LOCALMODEL"))
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(theme="light", effortLevel="WSLEFF"))
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace("on-request", "never").replace(
            "approval_policy", 'model = "mine"\nfoo = 1\napproval_policy'))
        before = snap(e.root)
        self.assertNotEqual(run(e, "sync.py").code, 0, "沒有 --force 時中止")
        self.assertEqual(snap(e.root), before, "中止時不寫入")
        r = run(e, "sync.py", ["--force"])
        self.assertEqual(r.code, 0, r.out)
        win = rj(e.win / ".claude/settings.json")
        self.assertEqual((win["theme"], win["model"]), ("dark", "LOCALMODEL"))
        self.assertNotIn("effortLevel", win)
        wsl = rj(e.wsl / ".claude/settings.json")
        self.assertEqual((wsl["theme"], wsl["effortLevel"]), ("dark", "WSLEFF"))
        self.assertNotIn("model", wsl)
        cfg = rd(e.win / ".codex/config.toml")
        self.assertIn('approval_policy = "on-request"', cfg)
        self.assertIn('model = "mine"', cfg)
        self.assertIn("foo = 1", cfg)
        self.assertNotIn("model_reasoning_effort", cfg)

    def test_codex_missing_keys_update_without_force(self):
        e = self.pushed()
        w(e.wsl / ".codex/config.toml", 'model = "mine"\n')
        r = run(e, "sync_codex.py", ["--check"])
        self.assertRegex(r.out, r"(?m)^update +.*config\.toml")
        r = run(e, "sync_codex.py")
        self.assertEqual(r.code, 0, r.out)
        cfg = rd(e.wsl / ".codex/config.toml")
        self.assertIn('model = "mine"', cfg)
        self.assertIn("approval_policy", cfg)
        self.assertNotIn("model_reasoning_effort", cfg)

    def test_pull_keeps_repo_ignored_fields(self):
        e = self.pushed()
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(model="WINMODEL", theme="light", effortLevel="zz"))
        edit_json(e.repo / "claude-settings.json", lambda o: o.pop("effortLevel"))
        w(e.win / ".codex/config.toml", 'model = "winmodel"\n' + rd(e.win / ".codex/config.toml").replace(
            "on-request", "never").replace('model = "gpt-x"', ""))
        r = run(e, "sync.py", ["--pull-win"])
        self.assertEqual(r.code, 0, r.out)
        s = rj(e.repo / "claude-settings.json")
        self.assertEqual((s["theme"], s["model"]), ("light", "sonnet"))
        self.assertNotIn("effortLevel", s)
        t = rd(e.repo / "codex-config.toml")
        self.assertIn('model = "gpt-x"', t)
        self.assertIn('model_reasoning_effort = "medium"', t)
        self.assertIn('approval_policy = "never"', t)

    def test_nested_effort_is_managed(self):
        e = self.pushed()
        edit_json(e.win / ".claude/settings.json", lambda o: o["modelSettings"]["m1"].update(effortLevel="high"))
        r = run(e, "sync_claude.py", ["--check-verbose"])
        self.assertIn("differs", r.out)
        self.assertIn('modelSettings.m1.effortLevel: "high" → "medium"', r.out)
        self.assertNotEqual(run(e, "sync_claude.py").code, 0)
        self.assertEqual(run(e, "sync_claude.py", ["--force"]).code, 0)
        self.assertEqual(rj(e.win / ".claude/settings.json")["modelSettings"]["m1"]["effortLevel"], "medium")
        edit_json(e.win / ".claude/settings.json", lambda o: o["modelSettings"]["m1"].update(effortLevel="high"))
        self.assertEqual(run(e, "sync_claude.py", ["--pull-win"]).code, 0)
        self.assertEqual(rj(e.repo / "claude-settings.json")["modelSettings"]["m1"]["effortLevel"], "high")

    def test_wsl_overlay_pull(self):
        e = self.pushed()
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(model="WSLMODEL"))
        repo_before = rd(e.repo / "claude-settings.json")
        r = run(e, "sync_claude.py", ["--pull-wsl"])
        self.assertEqual(r.code, 0, r.out)
        self.assertEqual(rd(e.repo / "claude-settings.json"), repo_before, "--pull-wsl 略過 settings.json")
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(theme="light"))
        before = snap(e.repo)
        r = run(e, "sync_claude.py", ["--pull-wsl"])
        self.assertNotEqual(r.code, 0)
        self.assertEqual(snap(e.repo), before, "受管設定不同時中止且不收回任何檔案")

    def test_order_format_array_type(self):
        e = self.pushed()
        s = rj(e.win / ".claude/settings.json")
        w(e.win / ".claude/settings.json", json.dumps(dict(reversed(list(s.items()))), separators=(",", ":")))
        w(e.win / ".codex/config.toml",
          'approval_policy = "on-request"  # 註解\n\n[tools.env]\nA = \'REPOTOML\'\n\n[tui]\nstatus_line = [ "a",   "b" ]\n\n[tui.keymap.editor]\ninsert_newline = ["ctrl-enter"]\n')
        r = run(e, "sync.py", ["--check"])
        self.assertEqual(r.code, 0)
        self.assertNotRegex(r.out, r"differs|update|missing")
        edit_json(e.win / ".claude/settings.json", lambda o: o["permissions"].update(allow=["B", "A"]))
        self.assertIn("differs", run(e, "sync_claude.py", ["--check"]).out, "JSON array 換序")
        edit_json(e.win / ".claude/settings.json", lambda o: o["permissions"].update(allow=["A", "B"]) or o.update(count="1"))
        self.assertIn("differs", run(e, "sync_claude.py", ["--check"]).out, "型別改變")
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(count=1))
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace('[ "a",   "b" ]', '["b", "a"]'))
        self.assertIn("differs", run(e, "sync_codex.py", ["--check"]).out, "TOML array 換序")

    def test_json_true_vs_one_and_int_vs_float_differ(self):
        e = self.pushed()
        edit_json(e.repo / "claude-settings.json", lambda o: o.update(flag=True))
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(flag=1))
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(flag=True))
        w(e.wsl / ".claude/settings.json", rd(e.wsl / ".claude/settings.json").replace('"count": 1,', '"count": 1.0,'))
        r = run(e, "sync_claude.py", ["--check-verbose"])
        self.assertRegex(r.out, r"(?m)^differs +.*win.*settings\.json")
        self.assertRegex(r.out, r"(?m)^differs +.*wsl.*settings\.json")
        self.assertIn("flag: 1 → true", r.out)
        self.assertIn("count: 1.0 → 1", r.out)

    def test_check_verbose_is_readonly_with_overview_and_diffs(self):
        e = self.pushed()
        edit_json(e.win / ".claude/keybindings.json", lambda o: o["bindings"][0].update(action="changed"))
        w(e.wsl / ".claude/CLAUDE.md", "# other rules\n")
        (e.win / ".claude/statusline.py").unlink()
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace('["ctrl-enter"]', '["ctrl-j"]'))
        before = snap(e.root)
        r = run(e, "sync.py", ["--check-verbose"])
        self.assertEqual(r.code, 0, r.out)
        self.assertRegex(r.out, r"(?m)^missing +.*statusline\.py")
        self.assertRegex(r.out, r"(?m)^same +")
        self.assertRegex(r.out, r"(?m)^differs +.*keybindings\.json")
        self.assertIn('bindings[0].action: "changed" → "x"', r.out)
        self.assertIn('tui.keymap.editor.insert_newline: ["ctrl-j"] → ["ctrl-enter"]', r.out)
        self.assertRegex(r.out, r"(?m)^\s+- # other rules")
        self.assertRegex(r.out, r"(?m)^\s+\+ # rules")
        self.assertEqual(snap(e.root), before, "bytes、修改時間不變，也不建立缺少的檔案")
        self.assertNotRegex(run(e, "sync.py", ["--check"]).out, r"changed|other rules")

    def test_sensitive_values_are_masked(self):
        e = self.pushed()

        def tweak(o):
            o.update(model="LEAKMODEL", env={"X": "LEAKENV"}, myToken="LEAKTOK",
                     nested={"ok": "visible-local", "apiKey": "LEAKKEY"}, auth={"deep": {"v": "LEAKAUTH"}})

        edit_json(e.win / ".claude/settings.json", tweak)
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace("REPOTOML", "LEAKTOML") + 'model = "LEAKCODEXMODEL"\n')
        v = run(e, "sync.py", ["--check-verbose"])
        allout = v.out
        for args in (["--check-verbose"], [], ["--force"]):
            allout += run(e, "sync_claude.py", args).out + run(e, "sync_codex.py", args).out
        self.assertNotIn("LEAK", allout)
        self.assertIn('nested.ok: "visible-local" → "visible-repo"', v.out)
        self.assertIn("***", v.out)

    def test_broken_json_diagnostic_has_no_content(self):
        e = self.pushed()
        w(e.win / ".claude/settings.json", '{"env": {"X": "LEAKBAD"} oops')
        r = run(e, "sync_claude.py", ["--check-verbose"])
        self.assertNotEqual(r.code, 0)
        self.assertNotIn("LEAK", r.out)
        self.assertIn("settings.json", r.out)

    def test_argument_conflicts_rejected_before_io(self):
        e = self.pushed()
        conflicts = [["--check", "--force"], ["--check-verbose", "--pull-win"], ["--check", "--pull-wsl"],
                     ["--check-verbose", "--force"], ["--pull-win", "--pull-wsl"], ["--win-only", "--pull-wsl"],
                     ["--chec"], ["--pull"], ["--win"]]  # 後三者為隱含縮寫，不接受
        for script in ("sync.py", "sync_claude.py", "sync_codex.py"):
            for cf in conflicts:
                with self.subTest(script=script, args=cf):
                    before = snap(e.root)
                    self.assertNotEqual(run(e, script, cf).code, 0)
                    self.assertEqual(snap(e.root), before)
                    self.assertNotEqual(run(e, script, cf, test_paths=False).code, 0)
                    self.assertFalse(e.wsl_called(), "在 WSL 呼叫前拒絕")

    def test_old_powershell_style_options_are_rejected(self):
        e = self.env()
        for old in ("-PullWin", "-CheckVerbose", "-TestWinHome"):
            self.assertNotEqual(run(e, "sync.py", [old]).code, 0)

    def test_test_paths_must_be_paired(self):
        e = self.env()
        for script in ("sync.py", "sync_claude.py", "sync_codex.py"):
            for one in (["--test-win-home", str(e.win)], ["--test-wsl-root", str(e.wsl)],
                        ["--test-win-home", " ", "--test-wsl-root", str(e.wsl)],
                        ["--test-win-home", str(e.win), "--test-wsl-root", ""]):
                with self.subTest(script=script, args=one):
                    r = run(e, script, ["--check", *one], test_paths=False)
                    self.assertNotEqual(r.code, 0)
                    self.assertRegex(r.out, r"成對|空字串")
            self.assertEqual(run(e, script, ["--check-verbose"]).code, 0, f"{script} 成對時可執行")
        self.assertFalse(e.wsl_called())
        self.assertEqual([p for p in list(e.win.rglob("*")) + list(e.wsl.rglob("*")) if p.is_file()], [], "檢查不建立檔案")

    def test_win_only_cli_does_not_touch_wsl_root(self):
        e = self.env()
        nope = e.root / "never-created"
        r = run(e, "sync.py", ["--win-only", "--test-win-home", str(e.win), "--test-wsl-root", str(nope)], test_paths=False)
        self.assertEqual(r.code, 0, r.out)
        self.assertTrue((e.win / ".claude/settings.json").exists())
        self.assertFalse(nope.exists())
        self.assertNotIn(str(nope), r.out)
        self.assertFalse(e.wsl_called())

    def test_aggregate_stops_after_first_failure_and_matches_individual_output(self):
        e = self.pushed()
        edit_json(e.win / ".claude/keybindings.json", lambda o: o["bindings"][0].update(action="changed"))
        r = run(e, "sync.py")
        self.assertNotEqual(r.code, 0)
        self.assertIn("== Claude ==", r.out)
        self.assertNotIn("== Codex ==", r.out)
        agg = run(e, "sync.py", ["--check"]).out
        for script in ("sync_claude.py", "sync_codex.py"):
            for line in filter(str.strip, re.split(r"\r?\n", run(e, script, ["--check"]).out)):
                self.assertIn(line, agg)

    def test_claude_success_is_not_rolled_back_when_codex_fails(self):
        e = self.pushed()
        edit_json(e.repo / "claude-settings.json", lambda o: o.update(theme="light"))
        edit_json(e.win / ".claude/settings.json", lambda o: o.update(theme="dark"))
        edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(theme="dark"))
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace("on-request", "never"))
        self.assertNotEqual(run(e, "sync.py").code, 0)  # Claude 先因 differs 中止
        self.assertEqual(run(e, "sync_claude.py", ["--force"]).code, 0)
        self.assertEqual(rj(e.win / ".claude/settings.json")["theme"], "light")
        r = run(e, "sync.py")
        self.assertNotEqual(r.code, 0)
        self.assertIn("== Codex ==", r.out)
        self.assertEqual(rj(e.win / ".claude/settings.json")["theme"], "light", "Claude 的變更不回復")

    def test_text_newline_and_trailing_blank_lines_are_bytes_compared(self):
        e = self.pushed()
        w(e.win / ".claude/CLAUDE.md", "# rules\r\n")
        w(e.wsl / ".claude/CLAUDE.md", "# rules\n\n\n")
        r = run(e, "sync_claude.py", ["--check-verbose"])
        self.assertEqual(len(re.findall(r"(?m)^differs +.*CLAUDE\.md", r.out)), 2)
        self.assertEqual(r.out.count("（僅 BOM、換行字元或結尾空行不同）"), 2)
        self.assertEqual(run(e, "sync_claude.py", ["--force"]).code, 0)
        for h in (e.win, e.wsl):
            self.assertEqual((h / ".claude/CLAUDE.md").read_bytes(), b"# rules\n")

    def test_utf8_bom_target_is_accepted_for_json_and_toml(self):
        e = self.pushed()
        for path in (e.win / ".claude/settings.json", e.win / ".codex/config.toml", e.wsl / ".claude/keybindings.json"):
            path.write_bytes(b"\xef\xbb\xbf" + path.read_bytes())
        before = snap(e.root)
        r = run(e, "sync.py", ["--check"])
        self.assertEqual(r.code, 0, r.out)
        self.assertNotRegex(r.out, r"differs|missing|update")
        self.assertEqual(run(e, "sync.py").code, 0)
        self.assertEqual(snap(e.root), before, "same 不改寫 BOM 目標")
        # 文字檔的 BOM 是 bytes 差異
        (e.win / ".claude/CLAUDE.md").write_bytes(b"\xef\xbb\xbf# rules\n")
        self.assertRegex(run(e, "sync_claude.py", ["--check"]).out, r"(?m)^differs +.*win.*CLAUDE\.md")

    def test_toml_preserves_crlf_and_trailing_blank_lines(self):
        e = self.env()
        (e.win / ".codex").mkdir(parents=True)
        (e.win / ".codex/config.toml").write_bytes(b'model = "mine"\r\n\r\n[other]\r\nx = 1\r\n\r\n\r\n')
        r = run(e, "sync_codex.py")
        self.assertEqual(r.code, 0, r.out)
        data = (e.win / ".codex/config.toml").read_bytes()
        self.assertFalse(data.startswith(b"\xef\xbb\xbf"))
        self.assertEqual(data.replace(b"\r\n", b"").count(b"\n"), 0, "全部維持 CRLF")
        self.assertTrue(data.endswith(b"\r\n\r\n\r\n"), "尾端空行保留在 EOF")
        self.assertIn(b'approval_policy = "on-request"', data)
        self.assertIn(b"[other]\r\nx = 1", data)
        # LF 目標維持 LF
        (e.wsl / ".codex").mkdir(parents=True, exist_ok=True)
        (e.wsl / ".codex/config.toml").write_bytes(b'model = "mine"\n\n')
        run(e, "sync_codex.py")
        self.assertNotIn(b"\r", (e.wsl / ".codex/config.toml").read_bytes())

    def test_stdout_is_utf8_even_with_legacy_encoding(self):
        e = self.pushed()
        w(e.win / ".claude/CLAUDE.md", "# 繁體中文 ✓\n")
        r = run(e, "sync_claude.py", ["--check-verbose"])  # run() 設 PYTHONIOENCODING=cp1252
        self.assertEqual(r.code, 0)
        self.assertIn("繁體中文 ✓", r.out)
        self.assertIn("- # 繁體中文 ✓", r.out)
        w(e.win / ".codex/config.toml", rd(e.win / ".codex/config.toml").replace("on-request", "從不"))
        self.assertIn('approval_policy: "從不" → "on-request"', run(e, "sync_codex.py", ["--check-verbose"]).out)

    def test_real_sources_roundtrip(self):
        e = self.env(real_sources=True)
        r = run(e, "sync.py", ["--check-verbose"])
        self.assertEqual(r.code, 0, r.out)
        self.assertNotRegex(r.out, r"(?m)^(same|differs)")
        r = run(e, "sync.py")
        self.assertEqual(r.code, 0, r.out)
        for h in (e.win, e.wsl):
            self.assertNotRegex(rd(h / ".claude/CLAUDE.md"), r"C:|/home/")
            self.assertFalse((h / ".codex/pstack-models.md").exists())
            self.assertNotIn("pstack", rd(h / ".codex/AGENTS.md"))
            self.assertNotIn("pstack", rd(h / ".claude/CLAUDE.md"))
            self.assertRegex(rd(h / ".claude/pstack-models.md"), r"(?m)^session hook: off")
        self.assertNotRegex(run(e, "sync.py", ["--check"]).out, r"differs|missing|update")
        before = e.hashes()
        self.assertEqual(run(e, "sync.py", ["--pull-win"]).code, 0)
        self.assertEqual(run(e, "sync.py", ["--pull-wsl"]).code, 0)
        self.assertEqual(e.hashes(), before, "Pull 往返後 repo 內容不變")


# ---------------------------------------------------------------------------
# 平台模式（in-process main(argv) + mock）
# ---------------------------------------------------------------------------

class PlatformTests(EnvTestCase):
    def test_win_only_never_resolves_wsl(self):
        e = self.env()
        nope = e.root / "never-created"
        with forbid_wsl(), mock.patch.object(c, "find_wsl", side_effect=AssertionError("不應解析 wsl")):
            for module in (sync, sync_claude, sync_codex):
                r = inproc(e, module, ["--win-only"], "windows", local=e.win)
                self.assertEqual(r.code, 0, r.out)
            self.assertTrue((e.win / ".claude/settings.json").exists())
            self.assertTrue((e.win / ".codex/config.toml").exists())
            self.assertEqual(list(e.wsl.iterdir()), [], "WSL home 未被存取")
            r = inproc(e, sync, ["--win-only", "--check", "--test-win-home", str(e.win), "--test-wsl-root", str(nope)], "windows")
            self.assertEqual(r.code, 0, r.out)
            self.assertFalse(nope.exists())
            self.assertNotIn("wsl", r.out.lower().replace(str(e.root).lower(), ""))
            r = inproc(e, sync, ["--win-only", "--pull-win"], "windows", local=e.win)
            self.assertEqual(r.code, 0, r.out)
            r = inproc(e, sync, ["--win-only", "--pull-wsl"], "windows", local=e.win)
            self.assertNotEqual(r.code, 0)
        self.assertFalse(e.wsl_called())

    def test_pull_win_does_not_query_wsl(self):
        e = self.env()
        inproc(e, sync_claude, ["--win-only"], "windows", local=e.win)
        with forbid_wsl():
            r = inproc(e, sync_claude, ["--pull-win"], "windows", local=e.win)
        self.assertEqual(r.code, 0, r.out)

    def test_wsl_local_push_overlay_and_pull(self):
        e = self.env()
        with forbid_wsl():
            for module in (sync_claude, sync_codex):
                r = inproc(e, module, ["--distro", "Bogus"], "wsl", local=e.wsl)  # --distro 在 WSL 本機被忽略
                self.assertEqual(r.code, 0, r.out)
            self.assertEqual(list(e.win.iterdir()), [], "不存取 Windows home")
            s = rj(e.wsl / ".claude/settings.json")
            self.assertEqual(s["statusLine"]["command"], "wsl-status")
            self.assertEqual(s["permissions"]["allow"], ["A", "B", "C"])
            self.assertNotIn("model", s)
            self.assertIn('approval_policy = "on-request"', rd(e.wsl / ".codex/config.toml"))
            self.assertRegex(inproc(e, sync, ["--check"], "wsl", local=e.wsl).out, r"(?m)^same +")
            self.assertNotRegex(inproc(e, sync, ["--check"], "wsl", local=e.wsl).out, r"differs|missing|update")
            edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(model="WSLMODEL"))
            before = e.hashes()
            self.assertEqual(inproc(e, sync, ["--pull-wsl"], "wsl", local=e.wsl).code, 0)
            self.assertEqual(e.hashes(), before)
            edit_json(e.wsl / ".claude/settings.json", lambda o: o.update(theme="light"))
            self.assertNotEqual(inproc(e, sync_claude, ["--pull-wsl"], "wsl", local=e.wsl).code, 0)
        self.assertFalse(e.wsl_called())

    def test_macos_local_push_overlay_and_pull(self):
        e = self.env()
        mac = e.root / "mac"
        mac.mkdir()
        with forbid_wsl():
            for module in (sync_claude, sync_codex):
                r = inproc(e, module, ["--distro", "Bogus"], "macos", local=mac)  # --distro 在 macOS 被忽略
                self.assertEqual(r.code, 0, r.out)
            self.assertEqual(list(e.win.iterdir()) + list(e.wsl.iterdir()), [], "不存取 win / wsl home")
            s = rj(mac / ".claude/settings.json")
            self.assertEqual(s["statusLine"]["command"], "mac-status")
            self.assertEqual(s["permissions"]["allow"], ["A", "B", "D"])
            self.assertNotIn("model", s)
            self.assertIn('approval_policy = "on-request"', rd(mac / ".codex/config.toml"))
            self.assertRegex(inproc(e, sync, ["--check"], "macos", local=mac).out, r"(?m)^same +")
            self.assertNotRegex(inproc(e, sync, ["--check"], "macos", local=mac).out, r"differs|missing|update")
            edit_json(mac / ".claude/settings.json", lambda o: o.update(model="MACMODEL"))
            before = e.hashes()
            self.assertEqual(inproc(e, sync, ["--pull-mac"], "macos", local=mac).code, 0)
            self.assertEqual(e.hashes(), before)
            edit_json(mac / ".claude/settings.json", lambda o: o.update(theme="light"))
            r = inproc(e, sync_claude, ["--pull-mac"], "macos", local=mac)
            self.assertNotEqual(r.code, 0)
            self.assertIn("macOS", r.out)
        self.assertFalse(e.wsl_called())

    def test_macos_rejects_other_platform_options(self):
        e = self.env()
        for args in (["--pull-win"], ["--pull-wsl"], ["--win-only"],
                     ["--test-win-home", str(e.win), "--test-wsl-root", str(e.wsl)]):
            for module in (sync, sync_claude, sync_codex):
                with self.subTest(args=args, module=module.__name__):
                    before = snap(e.root)
                    with forbid_wsl():
                        r = inproc(e, module, args, "macos", local=e.win)
                    self.assertNotEqual(r.code, 0)
                    self.assertEqual(snap(e.root), before)

    def test_pull_mac_rejected_on_windows_and_wsl(self):
        e = self.env()
        for plat in ("windows", "wsl"):
            for module in (sync, sync_claude, sync_codex):
                with self.subTest(plat=plat, module=module.__name__):
                    before = snap(e.root)
                    with forbid_wsl():
                        r = inproc(e, module, ["--pull-mac"], plat, local=e.wsl)
                    self.assertNotEqual(r.code, 0)
                    self.assertIn("--pull-mac", r.out)
                    self.assertEqual(snap(e.root), before)

    def test_pull_mac_conflicts(self):
        e = self.env()
        for args in (["--pull-mac", "--pull-win"], ["--pull-mac", "--pull-wsl"],
                     ["--check", "--pull-mac"], ["--check-verbose", "--pull-mac"]):
            for module in (sync, sync_claude, sync_codex):
                with self.subTest(args=args, module=module.__name__):
                    before = snap(e.root)
                    r = inproc(e, module, args, "macos", local=e.win)
                    self.assertNotEqual(r.code, 0)
                    self.assertEqual(snap(e.root), before)

    def test_wsl_local_with_test_root_ignores_test_win_home(self):
        e = self.env()
        nope = e.root / "never-created"
        with forbid_wsl():
            r = inproc(e, sync, ["--test-win-home", str(nope), "--test-wsl-root", str(e.wsl)], "wsl")
        self.assertEqual(r.code, 0, r.out)
        self.assertTrue((e.wsl / ".claude/settings.json").exists())
        self.assertFalse(nope.exists())

    def test_wsl_local_rejects_windows_targeted_options(self):
        e = self.env()
        for flag in ("--pull-win", "--win-only"):
            for module in (sync, sync_claude, sync_codex):
                with self.subTest(flag=flag, module=module.__name__):
                    before = snap(e.root)
                    with forbid_wsl():
                        r = inproc(e, module, [flag], "wsl", local=e.wsl)
                    self.assertNotEqual(r.code, 0)
                    self.assertEqual(snap(e.root), before)

    def test_unsupported_platforms_abort_without_io(self):
        e = self.env()
        before = snap(e.root)
        for plat in ("linux", "other"):
            for module in (sync, sync_claude, sync_codex):
                for args in ([], ["--force"], ["--pull-win"], ["--pull-wsl"], ["--check"], ["--win-only"]):
                    with self.subTest(plat=plat, module=module.__name__, args=args), forbid_wsl():
                        r = inproc(e, module, args, plat, local=e.win)
                        self.assertNotEqual(r.code, 0)
                        self.assertIn("尚未支援", r.out)
        self.assertEqual(snap(e.root), before)
        self.assertEqual(list(e.win.iterdir()), [])

    def test_unsupported_platform_with_test_paths_still_refuses(self):
        e = self.env()
        r = inproc(e, sync_claude, ["--test-win-home", str(e.win), "--test-wsl-root", str(e.wsl)], "linux")
        self.assertNotEqual(r.code, 0)
        self.assertEqual(list(e.win.iterdir()) + list(e.wsl.iterdir()), [])

    def test_fake_wsl_command_is_intercepted_on_windows_dual_mode(self):
        e = self.env()
        write_fake_wsl(e.bin, fail=False)
        calls = []

        def fake_unc(distro, home):
            calls.append((distro, home))
            return e.wsl

        path = str(e.bin) + os.pathsep + os.environ.get("PATH", "")
        with mock.patch.dict(os.environ, {"PATH": path}):
            found = c.find_wsl()
            self.assertIsNotNone(found, "PATH 上找不到假 wsl")
            self.assertEqual(Path(found).resolve().parent, e.bin.resolve(), "shutil.which 沒有解析到假 wsl，可能會執行真實 WSL")
            with mock.patch.object(c, "wsl_unc_root", side_effect=fake_unc):
                r = inproc(e, sync_claude, ["--check", "--distro", "Dx"], "windows", local=e.win)
        self.assertEqual(r.code, 0, r.out)
        self.assertTrue(e.wsl_called(), "假 wsl 應被呼叫")
        self.assertEqual(calls, [("Dx", WSL_FAKE_HOME)])
        self.assertIn(str(e.wsl), r.out)
        self.assertEqual(len(re.findall(r"(?m)^missing +", r.out)), 10)

    def test_failing_wsl_aborts_before_any_write(self):
        e = self.env()  # 假 wsl 結束碼 1
        path = str(e.bin) + os.pathsep + os.environ.get("PATH", "")
        with mock.patch.dict(os.environ, {"PATH": path}):
            r = inproc(e, sync_claude, [], "windows", local=e.win)
        self.assertNotEqual(r.code, 0)
        self.assertTrue(e.wsl_called())
        self.assertIn("WSL", r.out)
        self.assertEqual(list(e.win.iterdir()), [])


# ---------------------------------------------------------------------------
# Codex TOML（tomlkit）：in-process，--win-only 搭配 mock 平台，Windows／WSL 皆可執行
# ---------------------------------------------------------------------------

import tomllib  # noqa: E402

REPO_TOML = (
    'model = "gpt-x"\n'
    'approval_policy = "on-request"\n\n'
    '[tui]\nstatus_line = ["a", "b"]\n'
)
INTERLEAVED = "[a]\nx = 1\n\n[b]\ny = 1\n\n[a.c]\nz = 1\n"


class TomlTests(EnvTestCase):
    def setup(self, repo_toml=REPO_TOML, target=None):
        e = self.env()
        w(e.repo / "codex-config.toml", repo_toml)
        if target is not None:
            self.put(e, target)
        return e

    def put(self, e, target):
        p = e.win / ".codex/config.toml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(target if isinstance(target, bytes) else target.encode("utf-8"))
        if not (p.parent / "AGENTS.md").exists():
            w(p.parent / "AGENTS.md", rd(e.repo / "AGENTS.md"))  # 與 repo 相同，讓 AGENTS.md 為 same

    def codex(self, e, args=()):
        return inproc(e, sync_codex, [*args, "--win-only"], "windows", local=e.win)

    def pull(self, e):
        return inproc(e, sync_codex, ["--pull-win"], "windows", local=e.win)

    def cfg(self, e):
        return e.win / ".codex/config.toml"

    def tl(self, path):
        return tomllib.loads(Path(path).read_bytes().decode("utf-8"))

    def test_same_semantics_different_syntax_keeps_bytes_and_mtime(self):
        repo = 'n = 255\napproval_policy = "on-request"\nq = "it"\n\n[tui]\nstatus_line = ["a", "b"]\n'
        target = "# c\nn = 0xFF  # hex\napproval_policy = 'on-request'  # 單引號\nq = \"\"\"it\"\"\"\n\n[tui]\nstatus_line = [ \"a\",\n  \"b\" ]\n"
        e = self.setup(repo, target)
        before = snap(e.win)
        for args in (["--check"], ["--check-verbose"]):
            r = self.codex(e, args)
            self.assertEqual(r.code, 0, r.out)
            self.assertRegex(r.out, r"(?m)^same +.*config\.toml")
        self.assertEqual(self.codex(e).code, 0)
        self.assertEqual(snap(e.win), before)

    def test_case_type_and_order_differ_and_nan_is_same(self):
        repo = 's = "Abc"\nflag = true\nn = 1\nf = 1.0\nnan = nan\narr = [1, 2]\n'
        lines = {l.split(" =")[0]: l for l in repo.splitlines()}
        for key, bad in (("s", 's = "abc"'), ("flag", "flag = 1"), ("n", "n = 1.0"), ("f", "f = 1"), ("arr", "arr = [2, 1]")):
            with self.subTest(key=key):
                good = repo.replace(lines[key], bad)
                e = self.setup(repo, good)
                r = self.codex(e, ["--check-verbose"])
                self.assertRegex(r.out, r"(?m)^differs +.*config\.toml")
                self.assertIn(f"{key}:", r.out)
                before = snap(e.win)
                self.assertNotEqual(self.codex(e).code, 0, "differs 需要 --force")
                self.assertEqual(snap(e.win), before)
                self.assertEqual(self.codex(e, ["--force"]).code, 0)
                self.assertEqual(norm_for_test(self.tl(self.cfg(e))[key]), norm_for_test(tomllib.loads(repo)[key]))
        e = self.setup(repo, repo)
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^same +.*config\.toml")

    def test_complex_values_create_update_and_independent_parse(self):
        repo = (
            'model = "x"\nmodel_reasoning_effort = "high"\n'
            'multi = """\nline1\nline "two"\n"""\n'
            'inl = { a = 1, b = [1, 2], "c.d" = "v" }\n'
            'dotted.x = 1\n\n'
            '[projects."C:\\\\a.b"]\ntrust_level = "trusted"\n\n'
            '[tools.env]\nA = "REPOTOML"\n\n'
            '[[servers]]\nname = "one"\n\n[[servers]]\nname = "two"\n'
        )
        want = tomllib.loads(repo)
        for k in ("model", "model_reasoning_effort"):
            want.pop(k)
        e = self.setup(repo)
        r = self.codex(e)
        self.assertEqual(r.code, 0, r.out)
        self.assertEqual(self.tl(self.cfg(e)), want)
        self.assertNotIn(b"\r", self.cfg(e).read_bytes())
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^same +.*config\.toml")
        # 目標只有部分內容：inline table、AoT 與 quoted-key table 逐項補回，本機內容保留
        self.put(e, 'extra = "mine"\nmodel = "local"\n[mcp_servers.x]\ncommand = "c"  # 保留\n')
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^update +.*config\.toml")
        self.assertEqual(self.codex(e).code, 0)
        got = self.tl(self.cfg(e))
        for k, v in want.items():
            self.assertEqual(got[k], v)
        self.assertEqual((got["extra"], got["model"], got["mcp_servers"]["x"]["command"]), ("mine", "local", "c"))
        self.assertIn("# 保留", rd(self.cfg(e)))
        # inline table／AoT 是完整 value：其中一項不同即 differs，Force 以整個 value 取代
        self.put(e, rd(self.cfg(e)).replace("b = [1, 2]", "b = [1, 3]").replace('name = "two"', 'name = "zzz"'))
        out = self.codex(e, ["--check-verbose"]).out
        self.assertRegex(out, r"(?m)^differs")
        self.assertIn("inl:", out)
        self.assertIn("servers:", out)
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        got = self.tl(self.cfg(e))
        self.assertEqual((got["inl"], got["servers"], got["extra"]), (want["inl"], want["servers"], "mine"))

    def test_quoted_dotted_key_path_not_split(self):
        repo = '[projects."C:\\\\a.b"]\ntrust_level = "trusted"\n'
        target = '[projects."C:\\\\a"]\ntrust_level = "other"\n\n[projects."C:\\\\a.b"]\ntrust_level = "untrusted"\n'
        e = self.setup(repo, target)
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        got = self.tl(self.cfg(e))["projects"]
        self.assertEqual(got["C:\\a.b"]["trust_level"], "trusted")
        self.assertEqual(got["C:\\a"]["trust_level"], "other")

    def test_local_comments_and_unmanaged_content_preserved(self):
        target = '# 我的設定\nmodel = "mine"  # 自選\napproval_policy = "never"  # 手動改過\n\n[mcp_servers.s]\ncommand = "x"  # keep\n\n[tui]\n# tui 註解\nother = 1\n'
        e = self.setup(REPO_TOML, target)
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        text = rd(self.cfg(e))
        for frag in ("# 我的設定", 'model = "mine"  # 自選', "# 手動改過", "# keep", "# tui 註解", "other = 1"):
            self.assertIn(frag, text)
        got = self.tl(self.cfg(e))
        self.assertEqual((got["approval_policy"], got["tui"]["status_line"]), ("on-request", ["a", "b"]))

    def test_multiline_string_crlf_lf_semantics(self):
        repo_lf = 'approval_policy = "on-request"\ns = """a\nb"""\ne = "x\\r\\ny"\n'
        # repo LF、目標 CRLF（含實際 CRLF 的多行字串）：語意相同
        target = 'approval_policy = "on-request"\r\ns = """a\r\nb"""\r\ne = "x\\r\\ny"\r\n'
        e = self.setup(repo_lf, target)
        w(e.win / ".codex/AGENTS.md", rd(e.repo / "AGENTS.md"))
        before = snap(e.win)
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^same +.*config\.toml")
        self.assertEqual(self.codex(e).code, 0)
        self.assertEqual(snap(e.win), before)
        # 更新其他 key：合法更新不被誤判或拒絕，CRLF 保留，多行字串與跳脫的 \r\n 值不變
        self.put(e, target.replace("on-request", "never"))
        r = self.codex(e, ["--force"])
        self.assertEqual(r.code, 0, f"合法更新不應被拒絕：{r.out}")
        data = self.cfg(e).read_bytes()
        self.assertEqual(data.replace(b"\r\n", b"").count(b"\n"), 0)
        got = self.tl(self.cfg(e))
        self.assertEqual((got["approval_policy"], got["s"], got["e"]), ("on-request", "a\nb", "x\r\ny"))
        # repo 實際 CRLF、目標 LF 也相同
        e = self.setup('approval_policy = "on-request"\r\ns = """a\r\nb"""\r\n', 'approval_policy = "on-request"\ns = """a\nb"""\n')
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^same +.*config\.toml")
        # 跳脫的 \r\n 與 \n 是不同的值
        e = self.setup('e = "x\\r\\ny"\n', 'e = "x\\ny"\n')
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^differs +.*config\.toml")

    def test_aot_with_crlf_multiline_string_keeps_semantics(self):
        repo = 'approval_policy = "on-request"\n\n[[servers]]\nname = "one"\nnote = """a\nb"""\n'
        e = self.setup(repo, 'approval_policy = "never"\r\n')  # 缺 AoT，且 differs；目標 CRLF
        w(e.repo / "codex-config.toml", repo.replace("\n", "\r\n"))  # repo 實際 CRLF
        r = self.codex(e, ["--force"])
        self.assertEqual(r.code, 0, r.out)
        got = self.tl(self.cfg(e))
        self.assertEqual(got["servers"], [{"name": "one", "note": "a\nb"}])
        self.assertEqual(self.cfg(e).read_bytes().replace(b"\r\n", b"").count(b"\n"), 0)
        self.assertRegex(self.codex(e, ["--check"]).out, r"(?m)^same +.*config\.toml")
        # Pull：來源 CRLF AoT 收回 repo，語意為 LF
        self.put(e, 'approval_policy = "x"\r\n[[servers]]\r\nname = "two"\r\nnote = """c\r\nd"""\r\n')
        self.assertEqual(self.pull(e).code, 0)
        self.assertEqual(tomllib.loads(rd(e.repo / "codex-config.toml"))["servers"], [{"name": "two", "note": "c\nd"}])

    def test_new_target_is_lf_even_if_repo_is_crlf(self):
        e = self.setup(REPO_TOML.replace("\n", "\r\n"))
        self.assertEqual(self.codex(e).code, 0)
        data = self.cfg(e).read_bytes()
        self.assertNotIn(b"\r", data)
        self.assertNotIn(b"model", data)
        self.assertEqual(self.tl(self.cfg(e))["approval_policy"], "on-request")

    def test_trailing_blank_lines_preserved_on_in_place_update(self):
        target = 'approval_policy = "never"\r\n\r\n[tui]\r\nstatus_line = ["a", "b"]\r\n\r\n\r\n'
        e = self.setup(REPO_TOML, target)
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        data = self.cfg(e).read_bytes()
        self.assertEqual(data, target.replace('"never"', '"on-request"').encode())

    def test_no_eof_newline_is_preserved(self):
        e = self.setup(REPO_TOML, 'approval_policy = "never"\n[tui]\nstatus_line = ["a", "b"]')
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        self.assertEqual(self.cfg(e).read_bytes(), b'approval_policy = "on-request"\n[tui]\nstatus_line = ["a", "b"]')
        e = self.setup(REPO_TOML, 'approval_policy = "never"\n\n\n')  # 缺 [tui]：新 table 補在前面，EOF 空行保留
        self.assertEqual(self.codex(e, ["--force"]).code, 0)
        self.assertTrue(self.cfg(e).read_bytes().endswith(b"\n\n\n"))
        self.assertEqual(self.tl(self.cfg(e))["tui"]["status_line"], ["a", "b"])

    def test_inline_and_dotted_parent_are_compatible(self):
        repo = '[tui]\nstatus_line = ["a", "b"]\nextra = 1\n'
        for target in ('tui = { status_line = ["a", "b"] }\n', 'tui.status_line = ["a", "b"]\n', 'tui = { status_line = ["x"] }\n'):
            with self.subTest(target=target):
                e = self.setup(repo, target)
                self.assertNotEqual(self.codex(e, ["--check-verbose"]).code, 1)
                self.assertEqual(self.codex(e, ["--force"]).code, 0)
                self.assertEqual(self.tl(self.cfg(e))["tui"], {"status_line": ["a", "b"], "extra": 1}, rd(self.cfg(e)))
                if target.startswith("tui = {"):
                    self.assertIn("tui = {", rd(self.cfg(e)), "父 table 的 inline 表示法不被改寫")

    def test_parent_structure_conflict_aborts_without_writes(self):
        repo = '[tui]\nstatus_line = ["a"]\n'
        for target in ('tui = "SECRETVAL"\n', 'tui = ["SECRETVAL"]\n', '[[tui]]\nk = "SECRETVAL"\n'):
            with self.subTest(target=target):
                e = self.setup(repo, target)
                before = snap(e.win)
                for args in (["--check"], [], ["--force"]):
                    r = self.codex(e, args)
                    self.assertNotEqual(r.code, 0)
                    self.assertIn("結構衝突", r.out)
                    self.assertNotIn("SECRETVAL", r.out)
                    self.assertEqual(snap(e.win), before)

    def test_pull_conflict_aborts_without_partial_write(self):
        e = self.setup(REPO_TOML, 'approval_policy = "never"\ntui = 1\n')
        w(e.win / ".codex/AGENTS.md", "# pulled\n")
        before = snap(e.repo)
        r = self.pull(e)
        self.assertNotEqual(r.code, 0)
        self.assertIn("結構衝突", r.out)
        self.assertEqual(snap(e.repo), before)

    def test_invalid_toml_is_safe_and_atomic(self):
        for target in ('key = "LEAKBAD\n', 'a = 1\na = 2  # LEAKDUP\n', 'x = [ "LEAKBAD" \n', b"\xff\xfe LEAKBAD"):
            with self.subTest(target=target):
                e = self.setup(REPO_TOML, target)
                before = snap(e.win)
                for args in (["--check-verbose"], [], ["--force"]):
                    r = self.codex(e, args)
                    self.assertNotEqual(r.code, 0)
                    self.assertNotIn("LEAK", r.out)
                    self.assertIn("config.toml", r.out)
                    self.assertEqual(snap(e.win), before)
        e = self.setup('bad = "LEAKREPO\n')
        r = self.codex(e)
        self.assertNotEqual(r.code, 0)
        self.assertNotIn("LEAK", r.out)
        self.assertEqual(list(e.win.iterdir()), [])
        # Pull：來源壞掉時 repo 不變
        e = self.setup(REPO_TOML, 'x = "LEAKSRC\n')
        before = snap(e.repo)
        r = self.pull(e)
        self.assertNotEqual(r.code, 0)
        self.assertNotIn("LEAK", r.out)
        self.assertEqual(snap(e.repo), before)

    def test_out_of_order_tables_readonly_ok_but_writes_rejected(self):
        # same 與唯讀（含有差異）仍可檢查，bytes／mtime 不變
        for repo in ("[a]\nx = 1\n", "[a]\nx = 2\n", "[a]\nx = 1\nnew = 1\n", "[a]\nx = 1\n[d]\nq = 1\n"):
            with self.subTest(repo=repo):
                e = self.setup(repo, INTERLEAVED)
                w(e.win / ".codex/AGENTS.md", rd(e.repo / "AGENTS.md"))
                before = snap(e.win)
                for args in (["--check"], ["--check-verbose"]):
                    r = self.codex(e, args)
                    self.assertEqual(r.code, 0, r.out)
                    self.assertRegex(r.out, r"(?m)^(same|differs|update) +.*config\.toml")
                self.assertEqual(snap(e.win), before)
                if repo == "[a]\nx = 1\n":
                    self.assertEqual(self.codex(e).code, 0)  # same 不需寫入
                    self.assertEqual(snap(e.win), before)
                    continue
                self.assertIn("a.x: 1 → 2", self.codex(e, ["--check-verbose"]).out) if "x = 2" in repo else None
                # 推送／Force 在寫入前拒絕，所有目標 bytes／mtime 不變
                for args in ([], ["--force"]):
                    r = self.codex(e, args)
                    self.assertNotEqual(r.code, 0)
                    self.assertIn("交錯", r.out)
                    self.assertEqual(snap(e.win), before)

    def test_multiple_dotted_keys_of_same_prefix_are_conservatively_rejected_for_writes(self):
        # tomlkit 對同一前綴的多個 dotted key 回傳 OutOfOrderTableProxy；依 plan 保守拒絕寫入，唯讀仍可檢查
        target = 'dotted.x = 1\ndotted.y = "s"\n'
        e = self.setup('approval_policy = "on-request"\n', target)
        before = snap(e.win)
        self.assertEqual(self.codex(e, ["--check-verbose"]).code, 0)
        r = self.codex(e)
        self.assertNotEqual(r.code, 0)
        self.assertIn("交錯", r.out)
        self.assertEqual(snap(e.win), before)

    def test_out_of_order_aot_subtable_round_trip_rejected(self):
        aot = "[[x]]\nn = 1\n\n[y]\nq = 1\n\n[[x.sub]]\nm = 1\n"
        e = self.setup("[y]\nq = 2\n", aot)
        before = snap(e.win)
        self.assertEqual(self.codex(e, ["--check-verbose"]).code, 0)
        r = self.codex(e, ["--force"])
        self.assertNotEqual(r.code, 0)
        self.assertEqual(snap(e.win), before)

    def test_out_of_order_in_repo_rejects_pull_and_new_target(self):
        e = self.setup(INTERLEAVED)
        self.put(e, "[a]\nx = 5\n")
        w(e.win / ".codex/AGENTS.md", "# pulled\n")
        before = snap(e.repo)
        r = self.pull(e)
        self.assertNotEqual(r.code, 0)
        self.assertEqual(snap(e.repo), before)
        e = self.setup(INTERLEAVED)  # 目標不存在：整份 repo document 會被輸出，同樣拒絕
        before = snap(e.root)
        self.assertEqual(self.codex(e, ["--check"]).code, 0)
        self.assertNotEqual(self.codex(e).code, 0)
        self.assertEqual(snap(e.root), before)

    def test_out_of_order_in_copied_source_subtree_rejected(self):
        repo = ('[[x]]\nn = 1\n\n[x.a]\np = 1\n\n[x.b]\nq = 1\n\n[x.a.c]\nr = 1\n')
        sync_codex.load_tomlkit()
        import tomlkit
        self.assertTrue(sync_codex.contains_out_of_order(tomlkit.parse(repo)["x"]), "fixture 的 AoT 子樹需含 proxy")
        e = self.setup(repo, "other = 1\n")
        before = snap(e.win)
        self.assertEqual(self.codex(e, ["--check"]).code, 0)
        for args in ([], ["--force"]):
            r = self.codex(e, args)
            self.assertNotEqual(r.code, 0)
            self.assertIn("交錯", r.out)
            self.assertEqual(snap(e.win), before)

    def test_tomlkit_exposes_out_of_order_proxy_type(self):
        from tomlkit.container import OutOfOrderTableProxy
        import tomlkit
        sync_codex.load_tomlkit()
        doc = tomlkit.parse("[a]\nx = 1\n[b]\ny = 1\n[a.c]\nz = 1\n")
        self.assertTrue(sync_codex.contains_out_of_order(doc))
        self.assertIsInstance(doc["a"], OutOfOrderTableProxy)
        self.assertFalse(sync_codex.contains_out_of_order(tomlkit.parse("[a]\nx = 1\n[a.c]\nz = 1\n[b]\ny = 1\n")))

    def test_verify_failure_means_no_partial_write(self):
        e = self.setup(REPO_TOML, 'approval_policy = "never"\n')
        before = snap(e.root)
        with mock.patch.object(sync_codex, "verify_output", side_effect=c.SyncError("TOML 序列化後驗證失敗")):
            r = self.codex(e, ["--force"])
        self.assertNotEqual(r.code, 0)
        self.assertEqual(snap(e.root), before)

    def test_pull_updates_managed_keys_only_and_keeps_repo_trivia(self):
        repo = '# repo 註解\nmodel = "gpt-x"\napproval_policy = "on-request"  # repo inline\nlist = [1, 2]\n\n[tui]\nstatus_line = ["a", "b"]\n'
        e = self.setup(repo, 'model = "src"\napproval_policy = "never"\nlist = [3]\nmcp = "ignore-me"\n[tui]\nother = 1\n')
        r = self.pull(e)
        self.assertEqual(r.code, 0, r.out)
        self.assertIn("沒有 tui.status_line，略過", r.out)
        text = rd(e.repo / "codex-config.toml")
        got = tomllib.loads(text)
        self.assertEqual((got["model"], got["approval_policy"], got["list"]), ("gpt-x", "never", [3]))
        self.assertEqual(got["tui"], {"status_line": ["a", "b"]})
        self.assertNotIn("mcp", got)
        self.assertIn("# repo 註解", text)
        self.assertIn("# repo inline", text)

    def test_pull_ordinary_table_source_into_repo_inline_leaf(self):
        repo = '# 註解\nmodel = "gpt-x"\napproval_policy = "on-request"  # keep\noptions = { x = 1 }  # inline\n'
        source = 'model = "src"\napproval_policy = "never"\nextra = 1\n\n[options]\nx = 2\n\n[options.inner]\ny = 3\n\n[options.inner.deep]\nk = "v"\n'
        e = self.setup(repo, source)
        r = self.pull(e)
        self.assertEqual(r.code, 0, r.out)
        text = rd(e.repo / "codex-config.toml")
        got = tomllib.loads(text)
        self.assertEqual(got["options"], {"x": 2, "inner": {"y": 3, "deep": {"k": "v"}}})
        self.assertEqual((got["model"], got["approval_policy"]), ("gpt-x", "never"))
        self.assertNotIn("extra", got)
        self.assertIn("options = {", text)  # repo 仍是 inline 表示法
        self.assertIn("# 註解", text)
        self.assertIn("# keep", text)

    def test_pull_ordinary_table_source_with_crlf_and_escaped_crlf_strings(self):
        e = self.setup('options = { x = 1 }\n')
        self.put(e, b'[options]\r\nnote = """a\r\nb"""\r\nesc = "p\\r\\nq"\r\nlst = [1, 2]\r\n')
        r = self.pull(e)
        self.assertEqual(r.code, 0, r.out)
        got = tomllib.loads(rd(e.repo / "codex-config.toml"))["options"]
        self.assertEqual(got, {"note": "a\nb", "esc": "p\r\nq", "lst": [1, 2]})  # raw CRLF 正規化為 LF；跳脫的 \r\n 保留

    def test_pull_ordinary_table_source_with_out_of_order_subtree_is_rejected(self):
        e = self.setup('options = { x = 1 }\n', '[options]\nx = 2\n\n[options.a]\np = 1\n\n[options.b]\nq = 1\n\n[options.a.c]\nr = 1\n')
        before = snap(e.repo)
        r = self.pull(e)
        self.assertNotEqual(r.code, 0)
        self.assertIn("交錯", r.out)
        self.assertEqual(snap(e.repo), before)

    def test_tomlkit_dependency_preflight(self):
        e = self.env()
        before = snap(e.root)
        blocked = {"tomlkit": None, "tomlkit.container": None, "tomlkit.items": None}
        with mock.patch.dict(sys.modules, blocked):
            r = inproc(e, sync_codex, ["--win-only"], "windows", local=e.win)
            self.assertNotEqual(r.code, 0)
            self.assertIn("tomlkit", r.out)
            self.assertIn("pip install", r.out)
            self.assertEqual(snap(e.root), before)
            r = inproc(e, sync, ["--win-only"], "windows", local=e.win)  # 總入口不先寫 Claude
            self.assertNotEqual(r.code, 0)
            self.assertNotIn("== Claude ==", r.out)
            self.assertEqual(snap(e.root), before)
            r = inproc(e, sync_claude, ["--win-only"], "windows", local=e.win)  # 獨立 Claude 不需要 tomlkit
            self.assertEqual(r.code, 0, r.out)
        self.assertTrue((e.win / ".claude/settings.json").exists())
        self.assertFalse((e.win / ".codex").exists())

    def test_invalid_arguments_rejected_before_loading_dependency(self):
        e = self.env()
        with mock.patch.object(sync_codex, "load_tomlkit", side_effect=AssertionError("不應載入依賴")):
            for module in (sync, sync_codex):
                r = inproc(e, module, ["--check", "--force"], "windows", local=e.win)
                self.assertNotEqual(r.code, 0)
                self.assertIn("不能與", r.out)
            r = inproc(e, sync_codex, [], "linux", local=e.win)
            self.assertNotEqual(r.code, 0)
            self.assertIn("尚未支援", r.out)

    def test_sensitive_toml_values_masked_in_verbose(self):
        repo = '[tools.env]\nA = "REPOSEC"\n\n[auth]\ntoken = "REPOTOK"\n\n[plain]\nv = "visible-repo"\n'
        e = self.setup(repo, '[tools.env]\nA = "LEAKENV"\n\n[auth]\ntoken = "LEAKTOK"\n\n[plain]\nv = "visible-local"\n')
        r = self.codex(e, ["--check-verbose"])
        for secret in ("LEAK", "REPOSEC", "REPOTOK"):
            self.assertNotIn(secret, r.out)
        self.assertIn('plain.v: "visible-local" → "visible-repo"', r.out)
        self.assertIn("***", r.out)

    def test_nested_sensitive_keys_in_structured_values_are_masked(self):
        repo = (
            'options = { api_key = "FAKE_REPO_SECRET", mode = "x", inner = { env = { K = "FAKE_REPO_ENV" } } }\n'
            'list = [{ token = "FAKE_REPO_TOKEN", name = "n1" }]\n\n'
            '[[servers]]\nname = "one"\nenv = { A = "FAKE_REPO_AOT" }\npassword = "FAKE_REPO_PW"\n'
        )
        target = (
            'options = { api_key = "FAKE_LOCAL_SECRET", mode = "y", inner = { env = { K = "FAKE_LOCAL_ENV" } } }\n'
            'list = [{ token = "FAKE_LOCAL_TOKEN", name = "n2" }]\n\n'
            '[[servers]]\nname = "two"\nenv = { A = "FAKE_LOCAL_AOT" }\npassword = "FAKE_LOCAL_PW"\n'
        )
        e = self.setup(repo, target)
        outs = [self.codex(e, ["--check-verbose"]).out]
        outs.append(self.codex(e).out)  # 中止訊息
        outs.append(self.codex(e, ["--force"]).out)
        for out in outs:
            self.assertNotIn("FAKE_", out)
        verbose = outs[0]
        self.assertIn("options:", verbose)
        self.assertIn('mode = "y"', verbose)  # 非敏感的子欄位仍顯示
        self.assertIn("api_key = ***", verbose)
        self.assertEqual(self.tl(self.cfg(e))["options"]["api_key"], "FAKE_REPO_SECRET")  # 值本身仍正確同步

    def test_verbose_value_escapes_control_characters(self):
        e = self.setup('s = """a\nb"""\n', 's = "x"\n')
        out = self.codex(e, ["--check-verbose"]).out
        self.assertIn(r'"x" → "a\nb"', out)
        self.assertEqual(len([l for l in out.splitlines() if l.startswith("  s:")]), 1)


def norm_for_test(v):
    return (type(v).__name__, repr(v)) if not isinstance(v, list) else [norm_for_test(x) for x in v]


if __name__ == "__main__":
    unittest.main(verbosity=2)
