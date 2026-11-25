#!/usr/bin/env bash
# 以 asciinema 錄製第二個 WSL Herdr client; 由 WezTerm 命令面板「錄製 Herdr tab」呼叫.
# 用法: herdr-rec [名稱] 或 herdr-rec --file 檔名; 按 Ctrl+B, Q detach 即停止.
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

valid_name() {
  local name=$1
  local invalid_chars='[[:cntrl:]/:*?"<>|]'
  [[ $name != .* && $name != *\\* && $name != *$invalid_chars* && $name == *[![:space:]]* ]]
}

path_exists() {
  [[ -e $1 || -L $1 ]]
}

# 只允許刪除普通檔案, 並記住使用者所確認的版本.
recording_version() {
  local path
  for path in "$file" "$markers"; do
    if [[ -L $path ]]; then
      return 1
    elif [[ -f $path ]]; then
      stat -c '%d:%i:%s:%y:%z' -- "$path" || return 1
    elif [[ -e $path ]]; then
      return 1
    else
      printf '%s\n' absent
    fi
  done
}

lock_recording() {
  local digest
  digest=$(printf '%s' "$file" | sha256sum) || return 1
  exec 9>"$dir/.locks/${digest%% *}" || return 1
  flock -n 9
}

stage=''
committed=false
finish_replacement() {
  [[ -n $stage ]] || return 0
  if $committed; then
    rm -f -- "$stage/old.cast" "$stage/old.markers.json"
  else
    if path_exists "$stage/old.cast"; then
      ln -T -- "$stage/old.cast" "$file" && rm -- "$stage/old.cast"
    fi
    if path_exists "$stage/old.markers.json"; then
      ln -T -- "$stage/old.markers.json" "$markers" && rm -- "$stage/old.markers.json"
    fi
  fi
  rm -f -- "$stage/new.cast"
  if ! rmdir -- "$stage"; then
    printf '暫存檔保留於: %s\n' "$stage" >&2
  fi
  stage=''
}

fail_recording() {
  finish_replacement
  pause_exit "$1"
}

interactive=false
if [[ $# -eq 2 && $1 == --interactive-file ]]; then
  interactive=true
  name=${2%.cast}
elif [[ $# -eq 2 && $1 == --file ]]; then
  name=${2%.cast}
  if ! valid_name "$name"; then
    pause_exit '請輸入有效的錄影檔名 (不可使用路徑、控制字元或以 . 開頭).'
  fi
else
  name=${1:-}
  # 舊用法保留日期前綴, 並將不適合檔名的字元改為 -.
  name=$(printf '%s' "$name" | sed -E 's#[[:space:]/\\:*?"<>|]+#-#g; s#^-+##; s#-+$##')
  legacy_file="$(date +%Y%m%d-%H%M%S)${name:+-$name}.cast"
fi

mkdir -p "$dir/.locks"
chmod 700 "$dir" "$dir/.locks"
if $interactive; then
  trap finish_replacement EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  while true; do
    if valid_name "$name"; then
      file="$dir/$name.cast"
      markers="$dir/$name.markers.json"
      if ! lock_recording; then
        printf '無法鎖定 %s, 可能正在錄影, 請改名.\n' "$name.cast"
      elif ! path_exists "$file" && ! path_exists "$markers"; then
        break
      elif version=$(recording_version); then
        printf '\n%s 或其 marker 檔已存在.\n' "$name.cast"
        read -r -p '[Enter/r] 更改新錄影檔名  [d] 刪除原錄影及其 marker  [q] 取消: ' choice || exit 0
        case "$choice" in
          d)
            if [[ $(recording_version) != "$version" ]]; then
              printf '原檔已變更, 請重新確認.\n'
              exec 9>&-
              continue
            fi
            stage=$(mktemp -d -- "$dir/.replace-XXXXXXXX") || pause_exit '無法建立暫存目錄.'
            if path_exists "$file"; then
              mv -T -- "$file" "$stage/old.cast" || fail_recording "無法暫存: $file"
            fi
            if path_exists "$markers"; then
              mv -T -- "$markers" "$stage/old.markers.json" || fail_recording "無法暫存: $markers"
            fi
            break
            ;;
          q) exit 0 ;;
          ''|r) ;;
          *) exec 9>&-; continue ;;
        esac
      else
        printf '%s 或其 marker 無法取代, 請改名.\n' "$name.cast"
      fi
      exec 9>&-
    else
      printf '請輸入有效的錄影檔名 (不可使用路徑、控制字元或以 . 開頭).\n'
    fi
    read -er -i "$name" -p '新錄影檔名 (Ctrl+C 取消): ' name || exit 0
    name=${name%.cast}
  done
  printf '\033]1337;SetUserVar=PC_SETUP_HERDR_REC_READY=MQ==\007'
else
  file="$dir/${legacy_file:-$name.cast}"
  lock_recording || pause_exit "無法鎖定錄影檔: $file"
fi

capture_file=$file
if [[ -n $stage ]]; then
  capture_file="$stage/new.cast"
fi
if ! "$bin/asciinema" rec --quiet --title "${name:-herdr}" --command "$bin/herdr" "$capture_file"; then
  fail_recording "無法錄影: $file"
fi

if [ ! -s "$capture_file" ]; then
  fail_recording "沒有產生錄影檔: $file"
fi
chmod 600 "$capture_file" || fail_recording "無法設定錄影檔權限: $file"

if ! duration=$(python3 - "$capture_file" <<'PY'
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
); then
  fail_recording "無法讀取錄影檔: $file"
fi
if [[ -n $stage ]]; then
  if path_exists "$markers" || ! ln -T -- "$capture_file" "$file"; then
    fail_recording "錄影期間目標名稱已被佔用: $file"
  fi
  committed=true
  finish_replacement
fi
exec 9>&-

cat <<EOF

錄影完成
  檔案: $file
  長度: $duration
  大小: $(du -h "$file" | cut -f1)

重看 (4 倍速, 閒置上限 2 秒):
  asciinema play -s 4 -i 2 $(printf '%q' "$file")
轉 GIF (片段 1:00 到 2:30, 時間以加速後為準):
  agg --text-font-family 'Noto Sans Mono CJK TC' --speed 4 --idle-time-limit 2 --select 1:00..2:30 $(printf '%q %q' "$file" "${file%.cast}.gif")

EOF
read -rsn1 -p '按任意鍵關閉' || true
