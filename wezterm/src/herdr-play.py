#!/usr/bin/env python3
# 本機播放 ~/recordings/herdr 的 asciinema 錄影; 由 WezTerm 命令面板「播放 Herdr 錄影」呼叫.
# 用法: herdr-play [檔名] [--speed N]; Ctrl+C 或關閉 tab 即停止.
# 綁 WSL eth0 IP (NAT, 只有本機 Windows 連得到): wslrelay 轉不到只綁 127.0.0.1 的服務.
import argparse
import json
import math
import mimetypes
import os
import re
import tempfile
import shutil
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

IFACE = 'eth0'
PORT = 47615
REC_DIR = Path.home() / 'recordings' / 'herdr'
STATIC_DIR = Path.home() / '.local' / 'share' / 'herdr-player'
MARK_HEADER = 'X-Herdr-Play'
EXPLORER = '/mnt/c/Windows/explorer.exe'
MARKERS_MAX_BODY = 256 * 1024
MARKERS_MAX_COUNT = 1000
LABEL_MAX = 100
NEXT_MAX = 100000
RECORDINGS_LOCK = threading.Lock()


def safe_child(base, name, suffixes):
    """name 必須是 base 底下的單一檔名, 否則回傳 None (擋 path traversal)."""
    if not name or name.startswith('.') or '/' in name or '\\' in name:
        return None
    if Path(name).suffix not in suffixes:
        return None
    path = base / name
    if not path.is_file() or path.resolve().parent != base.resolve():
        return None
    return path


def markers_path(cast):
    """錄影旁掛的 marker 檔: <名稱>.markers.json."""
    return cast.with_suffix('.markers.json')


def rename_recording(files, targets):
    """用 hard link 保留原檔, 並確保目標存在時不覆蓋."""
    linked = []
    removed = []
    try:
        for source, target in zip(files, targets):
            os.link(source, target)
            linked.append(target)
        for source, target in zip(files, targets):
            source.unlink()
            removed.append((source, target))
    except OSError:
        for source, target in removed:
            os.link(target, source)
        for target in linked:
            target.unlink()
        raise


def delete_recording(files):
    stage = Path(tempfile.mkdtemp(dir=REC_DIR, prefix='.delete-'))
    moved = []
    try:
        for source in files:
            target = stage / source.name
            source.rename(target)
            moved.append((source, target))
    except OSError:
        for source, target in reversed(moved):
            target.rename(source)
        stage.rmdir()
        raise
    for _, target in moved:
        target.unlink()
    stage.rmdir()


def validate_markers(data):
    """[{t: 原始時間秒數 (>= 0), label: 1..LABEL_MAX 字}], 不合格回傳 None."""
    if not isinstance(data, list) or len(data) > MARKERS_MAX_COUNT:
        return None
    out = []
    for m in data:
        if not isinstance(m, dict) or set(m) != {'t', 'label'}:
            return None
        t, label = m['t'], m['label']
        if isinstance(t, bool) or not isinstance(t, (int, float)) or not math.isfinite(t) or t < 0:
            return None
        if not isinstance(label, str) or not label.strip() or len(label) > LABEL_MAX:
            return None
        out.append({'t': round(float(t), 3), 'label': label.strip()})
    out.sort(key=lambda m: m['t'])
    return out


def validate_payload(data):
    """{next: 下一個預設名稱編號 (刪除 marker 不倒退), markers: [...]}, 不合格回傳 None."""
    if not isinstance(data, dict) or set(data) != {'next', 'markers'}:
        return None
    nxt = data['next']
    if isinstance(nxt, bool) or not isinstance(nxt, int) or not 1 <= nxt <= NEXT_MAX:
        return None
    markers = validate_markers(data['markers'])
    if markers is None:
        return None
    return {'next': nxt, 'markers': markers}


def write_private(path, text):
    """先寫暫存檔再換上, 權限 600 (與錄影檔一致)."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(text)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


class Handler(BaseHTTPRequestHandler):
    server_version = 'herdr-play'

    def log_message(self, fmt, *args):
        # 只記錄開檔與錯誤, 避免狀態列輪詢洗版.
        status = str(args[1]) if len(args) > 1 else '5'
        if self.path.startswith('/cast/') or status[:1] in '45':
            sys.stderr.write('%s %s\n' % (self.log_date_time_string(), fmt % args))

    def send_body(self, status, body, ctype):
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header(MARK_HEADER, '1')
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, ctype):
        try:
            f = path.open('rb')
        except FileNotFoundError:
            return self.fail(404, 'not found')
        with f:
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(os.fstat(f.fileno()).st_size))
            self.send_header('Cache-Control', 'no-store')
            self.send_header(MARK_HEADER, '1')
            self.end_headers()
            shutil.copyfileobj(f, self.wfile)

    def fail(self, status, msg):
        self.send_body(status, msg.encode() + b'\n', 'text/plain; charset=utf-8')

    def origin(self):
        host, port = self.server.server_address[:2]
        return f'{host}:{port}'

    def marker_cast(self, path):
        """/api/markers/<name>.cast 對應的錄影檔, 不存在或不合法回傳 None."""
        name = urllib.parse.unquote(path[len('/api/markers/'):])
        return safe_child(REC_DIR, name, {'.cast'})

    def do_POST(self):
        if self.headers.get('Host') != self.origin():
            return self.fail(403, 'forbidden host')
        # 跨站送出需 CORS preflight 的 JSON 才能過 Content-Type 檢查, 再加 Origin 比對.
        if self.headers.get('Origin') != f'http://{self.origin()}':
            return self.fail(403, 'forbidden origin')
        ctype = (self.headers.get('Content-Type') or '').split(';')[0].strip().lower()
        if ctype != 'application/json':
            return self.fail(415, 'expect application/json')
        path = urllib.parse.urlsplit(self.path).path
        prefix = next((p for p in ('/api/markers/', '/api/recordings/') if path.startswith(p)), None)
        if prefix is None:
            return self.fail(404, 'not found')
        try:
            length = int(self.headers.get('Content-Length') or '-1')
        except ValueError:
            length = -1
        if length < 0 or length > MARKERS_MAX_BODY:
            return self.fail(413 if length > MARKERS_MAX_BODY else 411, 'bad length')
        try:
            payload = json.loads(self.rfile.read(length))
        except ValueError:
            return self.fail(400, 'invalid JSON')
        with RECORDINGS_LOCK:
            if prefix == '/api/recordings/':
                return self.change_recording(urllib.parse.unquote(path[len(prefix):]), payload)
            return self.save_markers(path, payload)

    def save_markers(self, path, payload):
        cast = self.marker_cast(path)
        if not cast:
            return self.fail(404, 'not found')
        payload = validate_payload(payload)
        if payload is None:
            return self.fail(400, 'invalid markers')
        write_private(markers_path(cast), json.dumps(payload, ensure_ascii=False, indent=1) + '\n')
        body = json.dumps(payload, ensure_ascii=False).encode()
        return self.send_body(200, body, 'application/json; charset=utf-8')

    def change_recording(self, name, payload):
        cast = safe_child(REC_DIR, name, {'.cast'})
        if not cast or cast.is_symlink():
            return self.fail(404, '找不到錄影')
        sidecar = markers_path(cast)
        if sidecar.is_symlink() or (sidecar.exists() and not sidecar.is_file()):
            return self.fail(409, 'marker 檔案無法移動或刪除')
        files = [cast, sidecar] if sidecar.is_file() else [cast]
        if not isinstance(payload, dict):
            return self.fail(400, '無效的錄影操作')
        try:
            if payload == {'action': 'delete'}:
                delete_recording(files)
                return self.send_body(204, b'', 'text/plain')
            stem = payload.get('stem')
            if set(payload) != {'action', 'stem'} or payload['action'] != 'rename' or not isinstance(stem, str):
                return self.fail(400, '無效的錄影操作')
            stem = stem.strip()
            if not stem or stem.startswith('.') or re.search(r'[\x00-\x1f\x7f/\\:*?"<>|\ud800-\udfff]', stem):
                return self.fail(400, '錄影名稱空白或含有不允許的字元')
            target = cast.with_name(stem + '.cast')
            target_sidecar = markers_path(target)
            if len(os.fsencode(target_sidecar.name)) > 255:
                return self.fail(400, '錄影名稱過長')
            if target != cast:
                if target_sidecar.exists() or target_sidecar.is_symlink():
                    raise FileExistsError(target_sidecar)
                rename_recording(files, [target, target_sidecar])
        except FileExistsError:
            return self.fail(409, '錄影名稱或 marker 檔案已存在')
        except OSError as e:
            return self.fail(500, f'檔案操作未完成 ({e.strerror or e})')
        body = json.dumps({'name': target.name}, ensure_ascii=False).encode()
        return self.send_body(200, body, 'application/json; charset=utf-8')

    def do_GET(self):
        # Host 必須是綁定的 IP:port, 防 DNS rebinding.
        if self.headers.get('Host') != self.origin():
            return self.fail(403, 'forbidden host')
        path = urllib.parse.urlsplit(self.path).path
        if path.startswith('/api/markers/'):
            with RECORDINGS_LOCK:
                cast = self.marker_cast(path)
                if not cast:
                    return self.fail(404, 'not found')
                mp = markers_path(cast)
                # 舊格式為純陣列, 由頁面相容處理; 沒有旁掛檔時 next 為 null (頁面自行起算).
                body = mp.read_bytes() if mp.is_file() else b'{"next": null, "markers": []}'
            return self.send_body(200, body, 'application/json; charset=utf-8')
        if path == '/':
            index = STATIC_DIR / 'index.html'
            if not index.is_file():
                return self.fail(500, f'missing {index}')
            return self.send_file(index, 'text/html; charset=utf-8')
        if path.startswith('/vendor/'):
            name = urllib.parse.unquote(path[len('/vendor/'):])
            file = safe_child(STATIC_DIR / 'vendor', name, {'.js', '.css'})
            if not file:
                return self.fail(404, 'not found')
            ctype = mimetypes.guess_type(file.name)[0] or 'application/octet-stream'
            return self.send_file(file, f'{ctype}; charset=utf-8')
        if path == '/api/list':
            items = []
            with RECORDINGS_LOCK:
                for f in REC_DIR.glob('*.cast'):
                    if not f.is_file():
                        continue
                    try:
                        st = f.stat()
                    except FileNotFoundError:
                        continue
                    items.append({'name': f.name, 'size': st.st_size, 'mtime': st.st_mtime})
            items.sort(key=lambda x: x['mtime'], reverse=True)
            body = json.dumps(items, ensure_ascii=False).encode()
            return self.send_body(200, body, 'application/json; charset=utf-8')
        if path.startswith('/cast/'):
            name = urllib.parse.unquote(path[len('/cast/'):])
            file = safe_child(REC_DIR, name, {'.cast'})
            if not file:
                return self.fail(404, 'not found')
            return self.send_file(file, 'text/plain; charset=utf-8')
        return self.fail(404, 'not found')


def wsl_ip():
    """IFACE 的 IPv4; WSL 每次啟動可能不同, 每次執行重新取得."""
    out = subprocess.run(['ip', '-4', '-o', 'addr', 'show', 'dev', IFACE],
                         capture_output=True, text=True, check=False).stdout
    m = re.search(r'\binet (\d+\.\d+\.\d+\.\d+)/', out)
    return m.group(1) if m else None


def already_running(host):
    try:
        req = urllib.request.Request(f'http://{host}:{PORT}/api/list')
        with urllib.request.urlopen(req, timeout=1) as resp:
            return resp.headers.get(MARK_HEADER) == '1'
    except (urllib.error.URLError, OSError):
        return False


def open_browser(url):
    try:
        # explorer.exe 開 URL 成功時 exit code 仍可能非 0, 不檢查.
        subprocess.run([EXPLORER, url], check=False, cwd='/mnt/c/')
    except OSError as e:
        print(f'無法開啟瀏覽器 ({e}), 請手動開啟: {url}', file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description='本機播放 Herdr asciinema 錄影')
    ap.add_argument('file', nargs='?', help='錄影檔名 (位於 ~/recordings/herdr)')
    ap.add_argument('--speed', type=float, help='開啟時的播放速度, 例如 4')
    args = ap.parse_args()

    query = {}
    if args.file:
        query['file'] = Path(args.file).name
    if args.speed:
        query['speed'] = f'{args.speed:g}'
    host = wsl_ip()
    if not host:
        sys.exit(f'找不到 {IFACE} 的 IPv4, 無法啟動.')
    url = f'http://{host}:{PORT}/' + (f'?{urllib.parse.urlencode(query)}' if query else '')

    if already_running(host):
        print(f'herdr-play 已在執行, 開啟 {url}')
        open_browser(url)
        return

    try:
        server = ThreadingHTTPServer((host, PORT), Handler)
    except OSError as e:
        sys.exit(f'無法綁定 {host}:{PORT}: {e}')
    server.daemon_threads = True
    print(f'herdr-play: {url}')
    print(f'錄影目錄: {REC_DIR}')
    print('Ctrl+C 或關閉此 tab 即停止.')
    open_browser(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        print('\n已停止.')


if __name__ == '__main__':
    main()
