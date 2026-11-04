#!/usr/bin/env bash
# 將 SSH host 以 sshfs 掛載到 ~/mnt/<host>，供 Herdr File Viewer（Ctrl+B, F）瀏覽遠端檔案。
# 部署位置：~/.local/bin/sshfs-mount（chmod +x，需 LF 換行）；需先安裝 sshfs。
set -euo pipefail

usage() {
    cat <<'EOF'
用法：
  sshfs-mount <host> [remotePath]   掛載 <host>:<remotePath> 到 ~/mnt/<host>（remotePath 預設為遠端 home）
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
remote="${2:-}"
target="$HOME/mnt/$host"
mkdir -p "$target"
if mountpoint -q "$target"; then
    echo "已掛載：$target"
    exit 0
fi
sshfs "$host:$remote" "$target" -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,follow_symlinks
echo "已掛載：$target"
echo "下一步：cd $target 然後按 Ctrl+B, F"
