# 成員建立

- 用 `herdr agent` 開新成員
- `herdr pane rename %ROLE% %TITLE%` (ROLE=角色, TITLE 簡述工作內容)
- 請為自己 herdr pane rename
- 開 Claude 成員時（`--kind claude`），要在 `--` 之後帶上 `--settings`，停用 `next-steps` plugin：

  ```
  herdr agent start <ROLE> --kind claude --pane <ID> -- --settings '{"enabledPlugins":{"next-steps@claude-community":false}}' [其他 claude 參數，例如 --model / --permission-mode]
  ```

- Codex 成員不受影響
