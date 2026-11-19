#!/usr/bin/env bash
# Fix (h): egress-check probes through "the proxy" and requires 403 for every deny host and 200 only for the
# read-only allow-list. The in-container probe script really runs here (bash /dev/tcp), against a local fake
# proxy on 127.0.0.1 (docker is a stub that rewrites proxy:8888 to it). No network beyond loopback.
. "$(dirname "$0")/lib.sh"; set +e
command -v python3 >/dev/null || { echo "python3 missing; SKIP"; exit 0; }
SB="$(sandbox_copy)"; BIN="$SB/.stubbin"; mkdir -p "$BIN"
PORT=$((20000 + RANDOM % 20000))
# Fake proxy: ALLOW_HOSTS answered 200, everything else 403 (like tinyproxy FilterDefaultDeny).
python3 -I - "$PORT" <<'PY' &
import socketserver, sys, os
allow = set(filter(None, os.environ.get("ALLOW_HOSTS", "cdn.builder.io").split(",")))
class H(socketserver.StreamRequestHandler):
    def handle(self):
        first = self.rfile.readline().decode(errors="replace").split()
        host = first[1].split(":")[0].replace("http://", "").strip("/") if len(first) > 1 else ""
        code = "200 Connection established" if host in allow else "403 Filtered"
        self.wfile.write(f"HTTP/1.0 {code}\r\n\r\n".encode())
class S(socketserver.ThreadingTCPServer): allow_reuse_address = True
S(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
FP=$!; sleep 1
cat > "$BIN/docker" <<STUB
#!/usr/bin/env bash
script="\${@: -1}"; exec bash -c "\${script//proxy\/8888/127.0.0.1\/$PORT}"
STUB
chmod +x "$BIN/docker"
run() { PATH="$BIN:$PATH" bash "$SB/scripts/egress-check.sh" 2>&1; }

rm -f "$SB/proxy/readonly-allowlist.txt"
out="$(run)"; rc=$?
expect_true "no read-only list: all denied, allow probe skipped (rc=$rc)" [ $rc -eq 0 ]
expect_true "says allow probe skipped" grep -q 'allow probe skipped' <<<"$out"
for h in www.trulyfreehome.com api.sticky.io limelightcrm.com a.klaviyo.com api.mailgun.net rest.avatax.com tfhcore.trulyfreehome.com builder.io; do
  expect_true "probes + denies $h" grep -q "ok: egress CONNECT $h -> 403" <<<"$out"
done
printf '%s\n' '# test' '^cdn\.builder\.io$' > "$SB/proxy/readonly-allowlist.txt"
out="$(run)"; rc=$?
expect_true "with read-only list: cdn.builder.io allowed (rc=$rc)" bash -c "[ $rc -eq 0 ] && grep -q 'ok: egress CONNECT cdn.builder.io -> 200' <<<\"\$1\"" _ "$out"
kill $FP 2>/dev/null; wait $FP 2>/dev/null
# Proxy that allows everything: every deny probe must fail health.
ALLOW_HOSTS="a.klaviyo.com,api.sticky.io,cdn.builder.io" python3 -I - "$PORT" <<'PY' &
import socketserver, sys
class H(socketserver.StreamRequestHandler):
    def handle(self):
        self.rfile.readline(); self.wfile.write(b"HTTP/1.0 200 Connection established\r\n\r\n")
class S(socketserver.ThreadingTCPServer): allow_reuse_address = True
S(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
FP=$!; sleep 1
out="$(run)"; rc=$?
expect_true "open proxy -> egress FAILED (rc=$rc)" [ $rc -eq 1 ]
expect_true "names a leaking host" grep -q 'egress CONNECT api.sticky.io: expected 403' <<<"$out"
kill $FP 2>/dev/null; wait $FP 2>/dev/null
rm -f "$SB/proxy/readonly-allowlist.txt"; out="$(PATH="$BIN:$PATH" bash "$SB/scripts/egress-check.sh" 2>&1)"; rc=$?
expect_true "proxy down -> egress FAILED (rc=$rc)" [ $rc -eq 1 ]
rm -rf "$SB"
done_tests
