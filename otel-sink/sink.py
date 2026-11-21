"""Local OTLP/HTTP sink for tfh-local (M11).

The member portal proxies browser OpenTelemetry exports to OTEL_EXPORTER_OTLP_ENDPOINT (/api/otel/traces ->
<endpoint>/v1/traces). Stage and prod have a collector; tfh-local pointed it at a refused loopback port, so every
export answered 500 and the suite's "no first-party 5xx" crawl failed whenever a batch was flushed. This sink answers
like a collector (200, empty partial-success body) and DISCARDS the payload: nothing is written or forwarded.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, body=b"{}"):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n:
            self.rfile.read(n)  # drain and drop
        self._reply(200 if self.path.rstrip("/") in ("/v1/traces", "/v1/metrics", "/v1/logs") else 404)

    def do_GET(self):
        self._reply(200 if self.path in ("/", "/health") else 404, b'{"status":"ok"}')

    def log_message(self, *args):  # no request logging (payloads are never stored either)
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 4318), Handler).serve_forever()
