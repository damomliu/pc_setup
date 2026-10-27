"""在 repo 的 ai-agent/ 與 Windows、WSL、macOS 之間同步 Claude Code 設定與規則。

預設：repo -> Windows 與 WSL（Windows 執行；--win-only 只同步 Windows）。WSL、macOS 執行時只同步本機。
  claude-settings.json      -> ~/.claude/settings.json（WSL、macOS 版先合併 claude-settings.wsl.json、claude-settings.macos.json）
  claude-keybindings.json   -> ~/.claude/keybindings.json
  claude-statusline.py      -> ~/.claude/statusline.py
  CLAUDE.md                 -> ~/.claude/CLAUDE.md
  claude-pstack-models.md   -> ~/.claude/pstack-models.md
忽略欄位：settings.json 頂層的 model、effortLevel（modelSettings.*.effortLevel 仍受管）。
  比對時排除；推送保留各目標原值、缺值不補入（含首次建立）；Pull 保留 repo 原值、不新增。
任何目標內容與 repo 不同時整批中止，不寫入；確認要覆蓋加 --force，要保留本機變更先用 --pull-win / --pull-wsl / --pull-mac 收回。
--pull-wsl、--pull-mac 要求來源 settings.json 等於 repo 合併結果（忽略欄位除外），相同則略過 settings.json，其餘檔案收回。
"""
import sys

sys.dont_write_bytecode = True

import copy  # noqa: E402

import sync_common as c  # noqa: E402
from sync_common import PlanItem, SyncError  # noqa: E402

# repo 檔 -> 家目錄下的相對路徑
FILE_MAP = {
    "claude-settings.json": ".claude/settings.json",
    "claude-keybindings.json": ".claude/keybindings.json",
    "claude-statusline.py": ".claude/statusline.py",
    "CLAUDE.md": ".claude/CLAUDE.md",
    "claude-pstack-models.md": ".claude/pstack-models.md",
}
SETTINGS = "claude-settings.json"
OVERLAYS = {"wsl": "claude-settings.wsl.json", "macos": "claude-settings.macos.json"}
# settings.json 的忽略欄位（僅頂層）
IGNORE_KEYS = ("model", "effortLevel")


def _loose_in(x, items) -> bool:
    """沿用 PowerShell -in 的語意：字串不分大小寫，其餘依型別與值比較。"""
    for y in items:
        if isinstance(x, str) and isinstance(y, str):
            if x.lower() == y.lower():
                return True
        elif c.canonical(x) == c.canonical(y):
            return True
    return False


def merge_settings(base: dict, over: dict, path: str = "") -> dict:
    """object 遞迴合併；僅頂層 permissions 的直接子陣列取聯集，其餘由 override 取代。"""
    for k, o in over.items():
        b = base.get(k)
        if isinstance(b, dict) and isinstance(o, dict):
            merge_settings(b, o, f"{path}.{k}")
        elif path == ".permissions" and isinstance(b, list) and isinstance(o, list):
            base[k] = list(b) + [x for x in o if not _loose_in(x, b)]
        else:
            base[k] = o
    return base


def merged_settings(repo, overlay: str) -> dict:
    return merge_settings(copy.deepcopy(c.read_json(repo / SETTINGS)), c.read_json(repo / overlay))


def new_plan_item(repo, src: str, target_info) -> PlanItem:
    target = target_info.root / FILE_MAP[src]
    exists = target.exists()
    src_path = repo / src
    if src.endswith(".json"):
        ignore = IGNORE_KEYS if src == SETTINGS else ()
        base = c.read_json(src_path)
        if src == SETTINGS and target_info.kind in OVERLAYS:
            base = merge_settings(base, c.read_json(repo / OVERLAYS[target_info.kind]))
        local = c.read_json(target) if exists else {}
        same = exists and c.json_same(local, base, ignore)
        data = c.to_json_bytes(c.join_ignored(base, base, local, ignore)) if ignore else c.read_bytes(src_path)
        state = "missing" if not exists else "same" if same else "differs"
        return PlanItem(target, data, "json", state, c.select_managed(local, ignore), c.select_managed(base, ignore))
    data = c.read_bytes(src_path)
    if not exists:
        state, local = "missing", ""
    else:
        raw = c.read_bytes(target)
        state, local = ("same" if raw == data else "differs"), c.decode_text(raw)
    return PlanItem(target, data, "text", state, local, c.decode_text(data))


def pull(ctx, repo) -> None:
    src = ctx.pull
    skip = ()
    overlay = OVERLAYS.get(src.kind)
    if overlay:
        # WSL／macOS settings.json 須等於 repo 合併結果（忽略欄位除外），否則無法判斷該回收到母版還是專屬檔
        src_settings = src.root / FILE_MAP[SETTINGS]
        if not c.json_same(c.read_json(src_settings), merged_settings(repo, overlay), IGNORE_KEYS):
            raise SyncError(f"已中止，未收回任何檔案。{src.name} settings.json 與 repo 合併結果不同：{src_settings}\n"
                            f"請手動編輯 {SETTINGS} 或 {overlay}。")
        skip = (SETTINGS,)
    # 先讀完所有來源、算好內容，再一次寫入
    writes = []
    for name, rel in FILE_MAP.items():
        if name in skip:
            continue
        frm, to = src.root / rel, repo / name
        if name == SETTINGS:
            have, mine = c.read_json(frm), c.read_json(to)
            data = None if c.json_same(have, mine, IGNORE_KEYS) else c.to_json_bytes(c.join_ignored(have, mine, mine, IGNORE_KEYS))
        else:
            data = c.read_bytes(frm)
        writes.append((frm, to, data))
    for frm, to, data in writes:
        if data is None:
            print(f"[same] {to}")
            continue
        c.write_bytes(to, data)
        print(f"{frm} -> {to}")


def sync(argv, repo, prog="sync_claude.py") -> None:
    ctx = c.build_context(argv, prog)
    if ctx.pull:
        return pull(ctx, repo)
    plan = [new_plan_item(repo, name, t) for name in FILE_MAP for t in ctx.targets]
    if ctx.args.check or ctx.args.check_verbose:
        c.write_plan_overview(plan)
        if ctx.args.check_verbose:
            for p in plan:
                if p.state == "same":
                    continue
                print(f"== {p.state}: {p.target}")
                if p.state == "missing":
                    continue
                if p.kind == "json":
                    c.write_json_diff(p.local, p.want)
                else:
                    c.write_text_diff(p.local, p.want)
        return
    c.report_plan_and_stop(plan, ctx.args.force)
    c.apply_plan(plan)


def main(argv=None, repo=None) -> int:
    return c.run_main(sync, argv, repo)


if __name__ == "__main__":
    raise SystemExit(main())
