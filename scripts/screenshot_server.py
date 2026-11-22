#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from PIL import Image

PORT = 9876
OUTPUT_DIR = os.path.realpath(os.path.abspath('prints/homologacao'))
os.makedirs(OUTPUT_DIR, exist_ok=True)

PNG_MAGIC = b'\x89PNG\r\n\x1a\n'
VALID_NAME_REGEX = re.compile(r'^[a-zA-Z0-9_-]{1,120}$')
ALLOWED_TARGETS = {'ios', 'android'}
ALLOWED_APPEARANCES = {'light', 'dark'}

class ScreenshotHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Log clean messages to stderr
        sys.stderr.write(f"[ScreenshotServer] {format % args}\n")

    def _send_error(self, code, message):
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(message.encode('utf-8'))

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
            return

        if parsed.path == '/appearance':
            mode = params.get('mode', [''])[0].strip().lower()
            if mode not in ALLOWED_APPEARANCES:
                self._send_error(400, f'Invalid appearance mode: {mode}. Allowed: {ALLOWED_APPEARANCES}')
                return
            res = subprocess.run(['xcrun', 'simctl', 'ui', 'booted', 'appearance', mode], capture_output=True)
            if res.returncode != 0:
                self._send_error(500, f'Failed to set appearance: {res.stderr.decode("utf-8")}')
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'APPEARANCE_SET')
            return

        if parsed.path == '/screenshot':
            name = params.get('name', [''])[0].strip()
            target = params.get('target', [''])[0].strip().lower()

            if not VALID_NAME_REGEX.match(name):
                self._send_error(400, f'Invalid screenshot name: {name}. Must match {VALID_NAME_REGEX.pattern}')
                return

            if target not in ALLOWED_TARGETS:
                self._send_error(400, f'Invalid target: {target}. Allowed: {ALLOWED_TARGETS}')
                return

            out_path = os.path.realpath(os.path.abspath(os.path.join(OUTPUT_DIR, f'{name}.png')))
            # Enforce that out_path is strictly inside OUTPUT_DIR
            if os.path.dirname(out_path) != OUTPUT_DIR:
                self._send_error(403, 'Path traversal attempt detected.')
                return

            # Execute capture tool
            if target == 'ios':
                res = subprocess.run(
                    ['xcrun', 'simctl', 'io', 'booted', 'screenshot', out_path],
                    capture_output=True,
                    timeout=15,
                )
                if res.returncode != 0:
                    self._send_error(500, f'simctl screenshot failed: {res.stderr.decode("utf-8")}')
                    return
            elif target == 'android':
                adb_bin = 'adb'
                user_adb = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')
                if os.path.exists(user_adb):
                    adb_bin = user_adb

                with open(out_path, 'wb') as f:
                    res = subprocess.run([adb_bin, 'exec-out', 'screencap', '-p'], stdout=f, timeout=15)
                if res.returncode != 0:
                    if os.path.exists(out_path):
                        os.remove(out_path)
                    self._send_error(500, f'adb screencap failed with exit code {res.returncode}')
                    return

            # Strict PNG validation
            if not os.path.exists(out_path) or os.path.getsize(out_path) < 100:
                if os.path.exists(out_path):
                    os.remove(out_path)
                self._send_error(500, f'Screenshot output file missing or empty: {out_path}')
                return

            with open(out_path, 'rb') as f:
                header = f.read(8)
            if header != PNG_MAGIC:
                os.remove(out_path)
                self._send_error(500, f'Invalid PNG magic bytes in {out_path}')
                return

            try:
                with Image.open(out_path) as img:
                    img.verify()
            except Exception as e:
                if os.path.exists(out_path):
                    os.remove(out_path)
                self._send_error(500, f'PNG verification failed: {e}')
                return

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK')
            return

        self._send_error(404, 'Endpoint not found.')

def run():
    # Strictly listen on loopback interface (127.0.0.1)
    server = HTTPServer(('127.0.0.1', PORT), ScreenshotHandler)
    print(f"Screenshot server listening strictly on http://127.0.0.1:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == '__main__':
    run()
