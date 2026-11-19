# Egress allow-list proxy (tinyproxy). Default DENY; allowed hosts come from allowlist.txt + readonly-allowlist.txt (mounted).
FROM alpine:3.20
RUN apk add --no-cache tinyproxy
COPY tinyproxy.conf /etc/tinyproxy/tinyproxy.conf
EXPOSE 8888
# Filter = allowlist.txt + readonly-allowlist.txt (both mounted read-only; CRs stripped so a CRLF checkout cannot turn
# '^host$' into a pattern that never matches / matches oddly; comments/blank lines dropped).
CMD ["sh", "-c", "cat /etc/tinyproxy/allowlist.txt /etc/tinyproxy/readonly-allowlist.txt 2>/dev/null | tr -d '\\r' | grep -vE '^[[:space:]]*(#|$)' > /tmp/filter.txt; exec tinyproxy -d -c /etc/tinyproxy/tinyproxy.conf"]
