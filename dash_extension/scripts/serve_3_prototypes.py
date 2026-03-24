import http.server
import socketserver
import threading
import os

ROOT = "/Users/yunsoo/Documents/dbauto"
SERVERS = [
    {"port": 8000, "file": "index_8000.html", "name": "강화정", "dir": "prototypes"},
    {"port": 8001, "file": "index_8001.html", "name": "김민수", "dir": "prototypes"},
    {"port": 8002, "file": "index_8002.html", "name": "이다민", "dir": "prototypes"},
    {"port": 8003, "file": "index.html", "name": "모바일 앱", "dir": "mobile"},
]

def make_handler(filename, directory):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=os.path.join(ROOT, directory), **kwargs)

        def do_GET(self):
            if self.path == '/' or self.path == '/index.html':
                self.path = '/' + filename
            return super().do_GET()

        def log_message(self, format, *args):
            pass  # 로그 숨김
    return Handler

threads = []
for srv in SERVERS:
    handler = make_handler(srv["file"], srv["dir"])
    httpd = socketserver.TCPServer(("", srv["port"]), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    threads.append((httpd, t))
    print(f"  ✅ 포트 {srv['port']} → 피해아동: {srv['name']}  http://localhost:{srv['port']}")

print(f"\n  총 {len(SERVERS)}개 서버 실행 중. Ctrl+C로 종료.\n")

try:
    threads[0][1].join()
except KeyboardInterrupt:
    print("\n종료합니다...")
    for httpd, _ in threads:
        httpd.shutdown()
