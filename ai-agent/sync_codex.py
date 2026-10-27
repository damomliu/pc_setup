"""在 repo 的 ai-agent/ 與 Windows、WSL 之間同步 Codex 設定與規則。

預設：repo -> Windows 與 WSL（Windows 執行；--win-only 只同步 Windows）。WSL 執行時只同步本機。
  AGENTS.md         -> ~/.codex/AGENTS.md（整檔覆寫；Codex 完整指引）
  codex-config.toml -> ~/.codex/config.toml（只合併 repo 列出的 key，其餘設定與註解原樣保留）
AGENTS.md 作為一般文字檔同步；不產生、比對或修改 pstack-models.md。
忽略欄位：config.toml 頂層的 model、model_reasoning_effort。
  比對時排除；推送保留各目標原值、缺值不補入（含首次建立）；Pull 保留 repo 原值、不新增。
config.toml 以 tomlkit 解析與寫回（需要 requirements.txt 的依賴）：
  repo 的普通 table 逐 leaf 管理；scalar、array、inline table、array-of-tables 視為完整 value。
  比較語意與型別（引號、註解、空白、數字進位等表示法不同視為 same；大小寫、array 順序、型別有意義）。
  沿用目標檔的換行字元，UTF-8 無 BOM；same 時不寫檔。
狀態：missing、same、update（只缺 key，不需 --force）、differs（受管 key 已存在但值不同）。
"""
import sys

sys.dont_write_bytecode = True

import copy  # noqa: E402
from collections.abc import Mapping  # noqa: E402
import tomllib  # noqa: E402
from datetime import date, datetime, time  # noqa: E402

import sync_common as c  # noqa: E402
from sync_common import PlanItem, SyncError  # noqa: E402

FILE_MAP = {
    "AGENTS.md": ".codex/AGENTS.md",
    "codex-config.toml": ".codex/config.toml",
}
CONFIG = "codex-config.toml"
# config.toml 的忽略欄位（僅頂層）
IGNORE_KEYS = ("model", "model_reasoning_effort")
TOMLKIT_VERSION = "0.15.2"

tk = None  # tomlkit 模組；由 load_tomlkit() 在參數與平台檢查後才載入
_OutOfOrder = None
_InlineTable = None
_AoT = None


def install_hint() -> str:
    if c.detect_platform() == "windows":
        return r"ai-agent\.venv\windows\Scripts\python.exe -m pip install -r ai-agent\requirements.txt"
    return "ai-agent/.venv/wsl/bin/python -m pip install -r ai-agent/requirements.txt"


def load_tomlkit() -> None:
    """載入 tomlkit；缺少或版本不符時中止，不 fallback。"""
    global tk, _OutOfOrder, _InlineTable, _AoT
    try:
        import tomlkit
        from tomlkit.container import OutOfOrderTableProxy
        from tomlkit.items import AoT, InlineTable
    except ImportError:
        raise SyncError(f"找不到 tomlkit=={TOMLKIT_VERSION}。請用目標環境的 Python 安裝：{install_hint()}") from None
    if tomlkit.__version__ != TOMLKIT_VERSION:
        raise SyncError(f"tomlkit 版本為 {tomlkit.__version__}，需要 {TOMLKIT_VERSION}。請重新安裝：{install_hint()}")
    tk, _OutOfOrder, _InlineTable, _AoT = tomlkit, OutOfOrderTableProxy, InlineTable, AoT


# ---------------------------------------------------------------------------
# TOML 讀取、比較與顯示（只用 tomlkit public API）
# ---------------------------------------------------------------------------

def parse_toml(data: bytes, path):
    """解析失敗時不帶出原始內容；回傳 (text, tomlkit document, tomllib 語意值)。

    tomlkit 負責 AST 編輯與輸出；比較用的語意值改由標準庫 tomllib（TOML 1.0）取得，
    因為 tomlkit 的 unwrap 會保留多行字串裡實際的 CRLF，tomllib 則正規化為 LF。
    """
    try:
        text = data.decode("utf-8-sig")
        return text, tk.parse(text), tomllib.loads(text)
    except Exception:
        raise SyncError(f"無法讀取或解析 TOML：{path}") from None


def sem_get(sem, path):
    """在 tomllib 語意值中取路徑；找不到（含父層不是 table）回傳 (False, None)。"""
    cur = sem
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return False, None
        cur = cur[k]
    return True, cur


def norm(v):
    """語意加型別的正規化：bool 與 int、int 與 float 不相同；兩個 NaN 相同。"""
    if isinstance(v, bool):
        return ("bool", v)
    if isinstance(v, int):
        return ("int", int(v))
    if isinstance(v, float):
        return ("float", "nan" if v != v else repr(float(v)))
    if isinstance(v, str):
        return ("str", str(v))
    if isinstance(v, Mapping):
        return ("table", tuple(sorted((str(k), norm(x)) for k, x in v.items())))
    if isinstance(v, (list, tuple)):
        return ("array", tuple(norm(x) for x in v))
    if isinstance(v, (datetime, date, time)):
        return (type(v).__name__, v.isoformat())
    return ("other", repr(v))


def is_table(v) -> bool:
    return isinstance(v, Mapping) and not isinstance(v, _InlineTable)


def managed_leaves(doc) -> list:
    """repo 的普通 table 遞迴列舉為 (tuple 路徑, item)；頂層忽略欄位不列入。"""
    out = []

    def walk(node, path):
        for k in node.keys():
            if not path and k in IGNORE_KEYS:
                continue
            v = node[k]
            if is_table(v):
                walk(v, path + (k,))
            else:
                out.append((path + (k,), v))

    walk(doc, ())
    return out


def lookup(doc, path):
    """回傳 ('ok', item) / ('missing', 第一個缺少的索引) / ('conflict', 擋路的非 table 的索引)。"""
    cur = doc
    for i, k in enumerate(path):
        if not isinstance(cur, Mapping):
            return "conflict", i - 1
        if k not in cur:
            return "missing", i
        cur = cur[k]
    return "ok", cur


def contains_out_of_order(node) -> bool:
    if isinstance(node, _OutOfOrder):
        return True
    if isinstance(node, Mapping):
        return any(contains_out_of_order(v) for v in node.values())
    if isinstance(node, list):
        return any(contains_out_of_order(v) for v in node)
    return False


def _fmt(v, path) -> str:
    if isinstance(v, Mapping):
        # 巢狀 key 依完整子路徑遮蔽（例如 inline table 內的 api_key、env 子樹）
        parts = [f"{tk.key(k).as_string()} = {'***' if c.is_sensitive_path(list(path) + [str(k)]) else _fmt(x, path + (str(k),))}"
                 for k, x in v.items()]
        return "{ " + ", ".join(parts) + " }" if parts else "{}"
    if isinstance(v, list):
        return "[" + ", ".join(_fmt(x, path) for x in v) + "]"
    return tk.item(v).as_string()


def fmt_value(v, path=()) -> str:
    """值的 TOML 表示（public API 產生），遮蔽巢狀敏感子路徑，並轉義實際的換行與控制字元。"""
    esc = {"\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return "".join(esc.get(ch, f"\\x{ord(ch):02x}" if ord(ch) < 0x20 or ord(ch) == 0x7F else ch) for ch in _fmt(v, tuple(path)))


def inline_from_native(v):
    """由 tomllib 的語意值以 public API 建出 inline AST（table 一律為 inline table）。"""
    if isinstance(v, dict):
        t = tk.inline_table()
        for k, x in v.items():
            t[k] = inline_from_native(x)
        return t
    if isinstance(v, list):
        a = tk.array()
        for x in v:
            a.append(inline_from_native(x))
        return a
    return tk.item(v)


def clone_value(item, sem=None):
    """複製 repo／來源的 value，不與原 AST 共用物件。

    sem 是該 value 在 tomllib 的語意值；來源是普通 table（repo 以 inline table 表示同一份資料）時，
    以它建出 inline table，避免 tomlkit unwrap 保留的多行字串 CRLF 改變語意。
    """
    if isinstance(item, bool):
        return item
    if contains_out_of_order(item):
        raise SyncError("無法安全複製（含有交錯宣告的 table）")
    if is_table(item):
        if not isinstance(sem, dict):
            raise SyncError("無法複製 TOML 設定值")
        return inline_from_native(sem)
    if isinstance(item, _AoT):
        return copy.deepcopy(item)  # 保留原始字串表示法（例如多行字串裡的 CRLF）
    try:
        value = tk.parse("v = " + item.as_string())["v"]
    except Exception:
        raise SyncError("無法複製 TOML 設定值") from None
    if contains_out_of_order(value):
        raise SyncError("無法安全複製（含有交錯宣告的 table）")
    return value


def build_missing(cur, rest, value):
    """在 table cur 底下補上 rest 路徑（最後一段為 leaf）。"""
    if len(rest) == 1:
        cur[rest[0]] = value
        return
    inline = isinstance(cur, _InlineTable)
    node = tk.inline_table() if inline else tk.table()
    node[rest[-1]] = value
    for key in reversed(rest[1:-1]):
        outer = tk.inline_table() if inline else tk.table(is_super_table=True)
        outer[key] = node
        node = outer
    cur[rest[0]] = node


def nl_of(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def eof_tail(text: str) -> str:
    """原文件結尾的換行（含尾端空行）；沒有 EOF 換行則為空字串。純檔案 framing，不解析 TOML。"""
    return text[len(text.rstrip("\r\n")):]


def render(doc, nl: str, tail=None) -> bytes:
    """序列化並統一成目標的換行字元；UTF-8 無 BOM。tail 不為 None 時，結尾換行還原成原文件的 EOF 狀態。"""
    out = tk.dumps(doc).replace("\r\n", "\n")
    if tail is not None:
        out = out.rstrip("\n") + tail.replace("\r\n", "\n")
    return (out.replace("\n", "\r\n") if nl == "\r\n" else out).encode("utf-8")


def guard_editable(text: str, doc, path) -> None:
    """寫入前的保守防護：原樣 round-trip 必須一致，且不含 library 可能重排的交錯 table。"""
    if tk.dumps(doc) != text:
        raise SyncError(f"無法安全編輯（TOML 原樣 round-trip 不一致，請手動整理）：{path}")
    if contains_out_of_order(doc):
        raise SyncError(f"無法安全編輯（含有交錯宣告的 table，請手動整理）：{path}")


def verify_output(data: bytes, expected: dict, path) -> None:
    """重新 parse 輸出，語意（含型別）必須等於預期的完整文件。"""
    try:
        ok = norm(tomllib.loads(data.decode("utf-8"))) == norm(expected)
    except Exception:
        ok = False
    if not ok:
        raise SyncError(f"TOML 序列化後驗證失敗，未寫入任何檔案：{path}")


def set_native(root: dict, path, value) -> None:
    for k in path[:-1]:
        root = root.setdefault(k, {})
    root[path[-1]] = value


def conflict_error(path, label) -> SyncError:
    return SyncError(f"TOML 結構衝突：{path} 的 {label} 不是 table，無法放入受管設定；請手動處理")


def merge_config(repo_path, target, readonly=False) -> PlanItem:
    """把 repo 受管 key 合併進目標 config，回傳寫入計畫。"""
    repo_text, repo_doc, repo_sem = parse_toml(c.read_bytes(repo_path), repo_path)
    leaves = [(p, sem_get(repo_sem, p)[1]) for p, _ in managed_leaves(repo_doc)]
    if not target.exists():
        # 由 repo document 的副本排除頂層忽略欄位後建立；新目標一律 LF
        changes = [(p, "(missing)", fmt_value(v, p)) for p, v in leaves]
        if readonly:
            return PlanItem(target, b"", "toml", "missing", changes=changes)
        guard_editable(repo_text, repo_doc, repo_path)
        _, doc, _ = parse_toml(repo_text.encode("utf-8"), repo_path)
        for k in IGNORE_KEYS:
            if k in doc:
                del doc[k]
        data = render(doc, "\n")
        verify_output(data, {k: v for k, v in repo_sem.items() if k not in IGNORE_KEYS}, target)
        return PlanItem(target, data, "toml", "missing", changes=changes)

    raw = c.read_bytes(target)
    text, doc, sem = parse_toml(raw, target)
    expected = copy.deepcopy(sem)
    state, changes, edits = "same", [], []
    for path, want in leaves:
        status, found = lookup(doc, path)
        if status == "conflict":
            raise conflict_error(target, ".".join(path[:found + 1]))
        if status == "ok":
            have = sem_get(sem, path)[1]
            if norm(have) != norm(want):
                state = "differs"
                changes.append((path, fmt_value(have, path), fmt_value(want, path)))
                edits.append((path, repo_item(repo_doc, path)))
        else:
            if state == "same":
                state = "update"
            changes.append((path, "(missing)", fmt_value(want, path)))
            edits.append((path, repo_item(repo_doc, path)))
        set_native(expected, path, want)
    if not edits or readonly:
        # same 與唯讀檢查只比較與列差異；排版／交錯結構的防護留到實際要寫入的計畫
        return PlanItem(target, raw, "toml", state, changes=changes)
    guard_editable(text, doc, target)
    for path, item in edits:
        value = clone_value(item)
        status, at = lookup(doc, path)  # 先前補入的父 table 會影響缺少的位置，套用時重新尋址
        if status == "ok":
            lookup(doc, path[:-1])[1][path[-1]] = value
        else:
            build_missing(lookup(doc, path[:at])[1], path[at:], value)
    data = render(doc, nl_of(text), eof_tail(text))
    verify_output(data, expected, target)
    return PlanItem(target, data, "toml", state, changes=changes)


def repo_item(doc, path):
    return lookup(doc, path)[1]


def text_item(target, data: bytes) -> PlanItem:
    if not target.exists():
        return PlanItem(target, data, "text", "missing", "", c.decode_text(data))
    raw = c.read_bytes(target)
    return PlanItem(target, data, "text", "same" if raw == data else "differs", c.decode_text(raw), c.decode_text(data))


def pull_config(src, cfg_from, cfg_to) -> bytes:
    """只把 repo 已列出的受管 key 改為來源現值；回傳新的 repo config bytes。"""
    _, have_doc, have_sem = parse_toml(c.read_bytes(cfg_from), cfg_from)
    text, want, want_sem = parse_toml(c.read_bytes(cfg_to), cfg_to)
    guard_editable(text, want, cfg_to)
    expected = copy.deepcopy(want_sem)
    for path, _ in managed_leaves(want):
        status, found = lookup(have_doc, path)
        if status == "conflict":
            raise conflict_error(cfg_from, ".".join(path[:found + 1]))
        if status == "missing":
            c.warn(f"{src.name} config.toml 沒有 {'.'.join(path)}，略過")
            continue
        theirs, mine = sem_get(have_sem, path)[1], sem_get(want_sem, path)[1]
        set_native(expected, path, theirs)
        if norm(theirs) != norm(mine):
            lookup(want, path[:-1])[1][path[-1]] = clone_value(found, theirs)
    data = render(want, nl_of(text), eof_tail(text))
    verify_output(data, expected, cfg_to)
    return data


def pull(ctx, repo) -> None:
    src = ctx.pull
    # 先讀取 AGENTS.md、算好 config.toml，全部成功才寫入 repo
    agents_from, agents_to = src.root / FILE_MAP["AGENTS.md"], repo / "AGENTS.md"
    agents = c.read_bytes(agents_from)
    cfg_from, cfg_to = src.root / FILE_MAP[CONFIG], repo / CONFIG
    cfg = pull_config(src, cfg_from, cfg_to)
    c.write_bytes(agents_to, agents)
    print(f"{agents_from} -> {agents_to}")
    c.write_bytes(cfg_to, cfg)
    print(f"{cfg_from} -> {cfg_to}（僅受管 key）")


def sync(argv, repo, prog="sync_codex.py") -> None:
    ctx = c.build_context(argv, prog, preflight=load_tomlkit)
    if ctx.pull:
        return pull(ctx, repo)
    agents = c.read_bytes(repo / "AGENTS.md")
    readonly = ctx.args.check or ctx.args.check_verbose
    plan = []
    for t in ctx.targets:
        plan.append(text_item(t.root / FILE_MAP["AGENTS.md"], agents))
        plan.append(merge_config(repo / CONFIG, t.root / FILE_MAP[CONFIG], readonly))
    if ctx.args.check or ctx.args.check_verbose:
        c.write_plan_overview(plan)
        if ctx.args.check_verbose:
            for p in plan:
                if p.state == "same":
                    continue
                print(f"== {p.state}: {p.target}")
                if p.state == "missing":
                    continue
                if p.kind == "text":
                    c.write_text_diff(p.local, p.want)
                    continue
                for path, local, want in p.changes:
                    c.write_value_diff(list(path), local, want)
        return
    c.report_plan_and_stop(plan, ctx.args.force)
    c.apply_plan(plan)


def main(argv=None, repo=None) -> int:
    return c.run_main(sync, argv, repo)


if __name__ == "__main__":
    raise SystemExit(main())
