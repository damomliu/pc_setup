#!/usr/bin/env bash
# 將 SSH host 的遠端 / 以 sshfs 掛載到 ~/mnt/<host>（遠端 /a/b 對應 ~/mnt/<host>/a/b），供 Yazi（Herdr Prefix, Y）瀏覽遠端檔案。
# 部署位置：~/.local/bin/sshfs-mount（chmod +x，需 LF 換行）；需先安裝 sshfs。
set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  sshfs-mount <host>                掛載 <host>:/ 到 ~/mnt/<host>
  sshfs-mount -u <host>             卸載 ~/mnt/<host>
  sshfs-mount -l                    列出目前的 sshfs 掛載
  sshfs-mount -h                    顯示說明
EOF
}

case "${1:-}" in
    -h|--help|"")
        usage
        [ -n "${1:-}" ] && exit 0
        exit 1
        ;;
    -l)
        findmnt -t fuse.sshfs || true
        exit 0
        ;;
    -u)
        host="${2:?請指定 host}"
        fusermount3 -u "$HOME/mnt/$host"
        echo "已卸載 ~/mnt/$host"
        exit 0
        ;;
esac

host="$1"
target="$HOME/mnt/$host"
mkdir -p "$target"
if mountpoint -q "$target"; then
    source="$(findmnt -n -o SOURCE --mountpoint "$target")"
    if [ "$source" != "$host:/" ]; then
        echo "$target 已掛載為 $source（非 $host:/），請先 sshfs-mount -u $host" >&2
        exit 1
    fi
    echo "已掛載：$target"
    exit 0
fi
sshfs "$host:/" "$target" -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,follow_symlinks
echo "已掛載：$target"
