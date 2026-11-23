#!/usr/bin/env bash
# 以 asciinema 錄製第二個 WSL Herdr client; 由 WezTerm 命令面板「錄製 Herdr tab」呼叫.
# 用法: herdr-rec [名稱]; 在錄影畫面按 Ctrl+B, Q detach 即停止.
set -euo pipefail

bin="$HOME/.local/bin"
dir="$HOME/recordings/herdr"

pause_exit() {
  printf '\n%s\n' "$1" >&2
  read -rsn1 -p '按任意鍵關閉' || true
  exit 1
}

[ -n "${HERDR_ENV:-}" ] && pause_exit '請從 WezTerm 命令面板執行, 不要在 Herdr pane 內執行.'
for exe in asciinema herdr; do
  [ -x "$bin/$exe" ] || pause_exit "找不到 $bin/$exe"
done

name=${1:-}
# 名稱只保留可安全用於檔名的字元, 其他改為 -.
name=$(printf '%s' "$name" | sed -E 's#[[:space:]/\\:*?"<>|]+#-#g; s#^-+##; s#-+$##')
file="$dir/$(date +%Y%m%d-%H%M%S)${name:+-$name}.cast"

mkdir -p "$dir"
chmod 700 "$dir"
"$bin/asciinema" rec --quiet --title "${name:-herdr}" --command "$bin/herdr" "$file"

if [ ! -s "$file" ]; then
  pause_exit "沒有產生錄影檔: $file"
fi
chmod 600 "$file"

duration=$(python3 - "$file" <<'PY'
import json, sys
total = 0.0
with open(sys.argv[1], encoding='utf-8') as f:
    version = json.loads(f.readline()).get('version')
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        t = float(json.loads(line)[0])
        # v3 存與前一事件的間隔, v2 存絕對時間.
        total = total + t if version == 3 else t
print(f'{int(total // 60)}m{int(total % 60):02d}s')
PY
)

cat <<EOF

錄影完成
  檔案: $file
  長度: $duration
  大小: $(du -h "$file" | cut -f1)

重看 (4 倍速, 閒置上限 2 秒):
  asciinema play -s 4 -i 2 '$file'
轉 GIF (片段 1:00 到 2:30, 時間以加速後為準):
  agg --text-font-family 'Noto Sans Mono CJK TC' --speed 4 --idle-time-limit 2 --select 1:00..2:30 '$file' '${file%.cast}.gif'

EOF
read -rsn1 -p '按任意鍵關閉' || true
