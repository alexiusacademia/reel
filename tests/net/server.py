# A small HTTP server for tests/net/http_check.sh: byte ranges, HEAD,
# redirects, a flaky path that fails twice, and an endless "radio" stream
# with optional ICY metadata. Run: python3 -I tests/net/server.py PORT ROOT
#
# Author: Alexius Academia
# Date: 2026-10-26

import http.server
import os
import sys
import time

PORT = int(sys.argv[1])
ROOT = sys.argv[2]
flaky = {}


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send_file(self, head):
        path = os.path.join(ROOT, self.path.split("?")[0].lstrip("/"))
        if not os.path.isfile(path):
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        data = open(path, "rb").read()
        rng = self.headers.get("Range")
        start, end = 0, len(data) - 1
        status = 200
        if rng and rng.startswith("bytes="):
            a, b = rng[6:].split("-")
            start = int(a) if a else len(data) - int(b)
            end = int(b) if (a and b) else len(data) - 1
            end = min(end, len(data) - 1)
            status = 206
        body = data[start:end + 1]
        self.send_response(status)
        self.send_header("Content-Type", "video/mp2t" if path.endswith(".ts") else "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(body)))
        if status == 206:
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, len(data)))
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def do_HEAD(self):
        if self.path.startswith("/redirect/"):
            return self.redirect()
        self.send_file(True)

    def redirect(self):
        self.send_response(302)
        self.send_header("Location", "/" + self.path[len("/redirect/"):])
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        p = self.path
        if p.startswith("/redirect/"):
            return self.redirect()
        if p.startswith("/flaky/"):
            n = flaky.get(p, 0)
            flaky[p] = n + 1
            if n < 2:
                self.send_response(503)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self.path = "/" + p[len("/flaky/"):]
            return self.send_file(False)
        if p.startswith("/radio"):
            return self.radio()
        self.send_file(False)

    def radio(self):
        # Endless MP3-like bytes: 0xFF 0xFB frame headers + filler, 16 KB/s.
        meta = self.headers.get("Icy-MetaData") == "1"
        metaint = 8192
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("icy-name", "Reel Test Radio")
        self.send_header("icy-genre", "Test")
        self.send_header("icy-br", "128")
        if meta:
            self.send_header("icy-metaint", str(metaint))
        self.end_headers()
        frame = bytes([0xFF, 0xFB, 0x90, 0x64]) + bytes(413)
        stream = frame * 40
        sent = 0
        song = 0
        try:
            while True:
                chunk = stream[:metaint]
                self.wfile.write(chunk)
                sent += len(chunk)
                if meta:
                    song += 1
                    t = ("StreamTitle='Song %d';StreamUrl='http://x/';" % song).encode()
                    k = (len(t) + 15) // 16
                    self.wfile.write(bytes([k]) + t + bytes(k * 16 - len(t)))
                self.wfile.flush()
                time.sleep(0.5)
        except Exception:
            pass


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
