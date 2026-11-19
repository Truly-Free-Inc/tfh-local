"""Klaviyo recorder for tfh-local.

Accepts any Klaviyo-shaped request, appends it to RECORDER_LOG (JSONL) and returns 202 with an empty JSON
body (200 for GET). Auth headers are redacted before writing. Assertions:
  GET  /__calls   -> JSON array of recorded calls
  POST /__reset   -> clear the log
NOTE: tf-api's Klaviyo base URL is a hard-coded constant (constants.KlaviyoAPIBaseURL); it needs an
env-override PR before tf-api traffic reaches this recorder. memberportal supports KLAVIYO_BASE_URL.
"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = os.environ.get("RECORDER_LOG", "/data/calls.jsonl")
PORT = int(os.environ.get("RECORDER_PORT", "8090"))
REDACT = {"authorization", "cookie", "x-api-key", "klaviyo-api-key"}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _record(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            body = json.loads(raw) if raw else None
        except ValueError:
            body = raw.decode("utf-8", "replace")
        headers = {k: ("<redacted>" if k.lower() in REDACT else v) for k, v in self.headers.items()}
        entry = {"ts": time.time(), "method": self.command, "path": self.path, "headers": headers, "body": body}
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")

    def do_GET(self):
        if self.path == "/__calls":
            calls = []
            if os.path.exists(LOG):
                with open(LOG, encoding="utf-8") as f:
                    calls = [json.loads(line) for line in f if line.strip()]
            return self._send(200, calls)
        if self.path == "/__health":
            return self._send(200, {"ok": True})
        self._record()
        self._send(200, {"data": []})

    def do_POST(self):
        if self.path == "/__reset":
            open(LOG, "w").close()
            return self._send(200, {"reset": True})
        self._record()
        self._send(202, {})

    do_PUT = do_PATCH = do_DELETE = do_POST

    def log_message(self, fmt, *args):
        print("klaviyo-recorder:", fmt % args)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
