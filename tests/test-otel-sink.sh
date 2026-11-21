#!/usr/bin/env bash
# M11: the local OTLP sink answers the portal's browser trace exports and drops them. Internal only, no egress.
. "$(dirname "$0")/lib.sh"
set +e
C="$T_ROOT/docker-compose.yml"; S="$T_ROOT/otel-sink/sink.py"
block() { awk '/^  otel-sink:/{f=1;print;next} f&&/^  [a-z]/{exit} f' "$C"; }
expect_true  "otel-sink service exists"                 grep -q '^  otel-sink:' "$C"
expect_false "otel-sink publishes no host port"         sh -c "$(declare -f block); C='$C'; block | grep -q 'ports:'"
expect_true  "otel-sink is on the internal network"     sh -c "$(declare -f block); C='$C'; block | grep -q 'networks: \[internal\]'"
expect_true  "portal exports go to the sink"            grep -q 'OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-sink:4318' "$C"
expect_true  "otel-sink bypasses the proxy (NO_PROXY)"  grep -q 'NO_PROXY: .*otel-sink' "$C"
expect_false "sink makes no outbound connections"       grep -Eq 'urllib|requests|http\.client|socket\.create_connection|\.connect\(' "$S"
expect_false "sink stores nothing"                      grep -Eq 'open\(|write_text|jsonl' "$S"
done_tests
