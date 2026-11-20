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

# EXTERNALS=real (Michael 2026-11-20): the reviewed Sticky/TF dev hosts must be 200 (Sticky API host shown masked),
# everything else incl. other limelightcrm.com hosts and the prod TF API host still 403.
printf '%s\n' '# test' '^cdn\.builder\.io$' > "$SB/proxy/readonly-allowlist.txt"
printf '%s\n' EXTERNALS=real STICKY_DOMAIN=limelightcrm.com STICKY_APP_KEY=dummyappkey > "$SB/.env"
ALLOW_HOSTS="cdn.builder.io,limelightcrm.com,api.dev.trulyfree.com,dummyappkey.limelightcrm.com" python3 -I - "$PORT" <<'PY' &
import socketserver, sys, os
allow = set(os.environ["ALLOW_HOSTS"].split(","))
class H(socketserver.StreamRequestHandler):
    def handle(self):
        first = self.rfile.readline().decode(errors="replace").split()
        host = first[1].split(":")[0].replace("http://", "").strip("/") if len(first) > 1 else ""
        self.wfile.write(f"HTTP/1.0 {'200 Connection established' if host in allow else '403 Filtered'}\r\n\r\n".encode())
class S(socketserver.ThreadingTCPServer): allow_reuse_address = True
S(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
FP=$!; sleep 1
out="$(run)"; rc=$?
expect_true "real: egress OK (rc=$rc)" [ $rc -eq 0 ]
for h in limelightcrm.com api.dev.trulyfree.com '<STICKY_APP_KEY>.limelightcrm.com'; do
  expect_true "real: allows $h" grep -qF "ok: egress CONNECT $h -> 200" <<<"$out"
done
for h in api.trulyfree.com www.limelightcrm.com api.limelightcrm.com sticky.io a.klaviyo.com; do
  expect_true "real: still denies $h" grep -q "ok: egress CONNECT $h -> 403" <<<"$out"
done
expect_false "real: never prints the Sticky app key" grep -q dummyappkey <<<"$out"
printf '%s\n' EXTERNALS=offline > "$SB/.env"
out="$(run)"; rc=$?
expect_true "offline against a real-mode proxy -> egress FAILED (rc=$rc)" [ $rc -eq 1 ]
expect_true "offline names the reachable TF dev host" grep -q 'egress CONNECT api.dev.trulyfree.com: expected 403' <<<"$out"
kill $FP 2>/dev/null; wait $FP 2>/dev/null
rm -rf "$SB"
done_tests
