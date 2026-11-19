#!/usr/bin/env bash
# Fix (f): .gitleaks.toml catches a planted token, ignores Jira keys / empty NAME= lines; check-secrets runs it.
. "$(dirname "$0")/lib.sh"; set +e
command -v gitleaks >/dev/null || { echo "test-gitleaks.sh: gitleaks not installed; SKIP"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tfh-local-gl.XXXXXX")"
# The planted token is built at runtime so this file never contains one.
tok="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
mkdir -p "$TMP/bad" "$TMP/ok"
printf 'GITHUB_TOKEN=%s\n' "$tok" > "$TMP/bad/x.env"
printf '# make verify KEY=TFHFUNNEL-1234\nSITEMAP_S3_KEY=\nOTHER=\n' > "$TMP/ok/x.env"
gl() { gitleaks dir --config "$T_ROOT/.gitleaks.toml" --redact --no-banner --log-level error --exit-code 1 "$1" >/dev/null 2>&1; }
expect_false "planted GitHub token is a leak" gl "$TMP/bad"
expect_true  "Jira key + empty NAME= lines are not leaks" gl "$TMP/ok"
expect_true  "check-no-secrets.sh runs gitleaks git" grep -q 'gitleaks git --config' "$T_ROOT/scripts/check-no-secrets.sh"
expect_true  "CI workflow scans full history" grep -q 'fetch-depth: 0' "$T_ROOT/.github/workflows/gitleaks.yml"
expect_true  "repo history is clean" gitleaks git --config "$T_ROOT/.gitleaks.toml" --redact --no-banner --log-level error --exit-code 1 "$T_ROOT"
rm -rf "$TMP"
done_tests
