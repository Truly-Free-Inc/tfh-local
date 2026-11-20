#!/usr/bin/env bash
# Fix (d): seed/auth-users.sh runs preflight first, uses load_env, and never puts a password on argv.
# docker/curl are replaced by recording stubs (no containers touched); every argv they receive is checked.
. "$(dirname "$0")/lib.sh"; set +e
SB="$(sandbox_copy)"; dummy_env "$SB"
PW_C="cust-Secret-$RANDOM-$RANDOM"; PW_A="admin-Secret-$RANDOM-$RANDOM"
cat >> "$SB/.env" <<ENV
TEST_CUSTOMER_PORTAL_EMAIL=test@tfh-local.test
TEST_CUSTOMER_PORTAL_PASSWORD=$PW_C
LOCAL_ADMIN_EMAIL=local-admin@trulyfreehome.com
LOCAL_ADMIN_PASSWORD=$PW_A
ENV
BIN="$SB/.stubbin"; LOG="$SB/.stublog"; mkdir -p "$BIN" "$LOG"
cat > "$BIN/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "docker $*" >> "$STUBLOG/argv"
case "$*" in *" config"*) exit 0 ;; esac
case "$*" in *psql*) cat >> "$STUBLOG/docker-stdin" ;; esac
case "$*" in *"psql -At"*) echo "customer id=1 name=test test auth_row=true" ;; *"./main"*) echo "job ok" ;; esac
STUB
cat > "$BIN/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "curl $*" >> "$STUBLOG/argv"
out=""; prev=""; for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
case "$*" in *"@-"*) cat >> "$STUBLOG/curl-stdin"; echo >> "$STUBLOG/curl-stdin" ;; esac
[ -n "$out" ] && echo '{"id":"0a0a0a0a-0b0b-0c0c-0d0d-0e0e0e0e0e0e"}' > "$out"
case "$*" in *"-w"*) printf 201 ;; *) echo '[{"id":"0a0a0a0a-0b0b-0c0c-0d0d-0e0e0e0e0e0e"}]' ;; esac
STUB
chmod +x "$BIN"/*
out="$(STUBLOG="$LOG" PATH="$BIN:$PATH" perl -e 'alarm shift; exec @ARGV' 60 bash "$SB/seed/auth-users.sh" 2>&1 </dev/null)"; rc=$?
expect_true "seed exits 0 with stubs (rc=$rc)" [ $rc -eq 0 ]
[ $rc -eq 0 ] || printf '%s\n' "$out" | tail -8 >&2
expect_true "preflight ran first" bash -c "printf '%s\n' \"\$1\" | head -1 | grep -q 'preflight: OK'" _ "$out"
expect_false "customer password never on argv" grep -qF -- "$PW_C" "$LOG/argv"
expect_false "admin password never on argv"    grep -qF -- "$PW_A" "$LOG/argv"
expect_false "passwords never printed"         grep -qF -e "$PW_C" -e "$PW_A" <<<"$out"
expect_true  "customer password sent on stdin to Kratos" grep -qF -- "$PW_C" "$LOG/curl-stdin"
expect_true  "admin password sent on stdin to Kratos"    grep -qF -- "$PW_A" "$LOG/curl-stdin"
expect_true  "Kratos admin is loopback only" bash -c "grep '^curl' '$LOG/argv' | grep -v 'http://127.0.0.1:14434/admin/identities' | wc -l | grep -qx ' *0'"
expect_false "no -password= flag anywhere in seed" grep -q -- '-password=' "$T_ROOT/seed/auth-users.sh"
expect_false "seed does not source .env with '.' (uses load_env)" grep -qE '^\s*(set -a;\s*)?\. \./\.env' "$T_ROOT/seed/auth-users.sh"
# Domain guard: exactly local-admin@trulyfreehome.com is allowed for the admin; any other company/gmail address is refused.
seed_with() { # seed_with KEY VALUE: rerun with one .env value replaced; prints rc + output
  sed -i.bak -E "s|^$1=.*|$1=$2|" "$SB/.env"; rm -f "$SB/.env.bak"
  STUBLOG="$LOG" PATH="$BIN:$PATH" perl -e 'alarm shift; exec @ARGV' 60 bash "$SB/seed/auth-users.sh" 2>&1 </dev/null; echo "rc=$?"
}
o="$(seed_with LOCAL_ADMIN_EMAIL Local-Admin@TrulyFreeHome.com)"; expect_true "admin local-admin@trulyfreehome.com (any case) allowed" grep -q 'rc=0' <<<"$o"
o="$(seed_with LOCAL_ADMIN_EMAIL someone@trulyfreehome.com)";     expect_true "any other company admin email refused" grep -q 'REFUSED: LOCAL_ADMIN_EMAIL' <<<"$o"
o="$(seed_with LOCAL_ADMIN_EMAIL x.local-admin@trulyfreehome.com)"; expect_true "look-alike admin email refused" grep -q 'REFUSED: LOCAL_ADMIN_EMAIL' <<<"$o"
o="$(seed_with LOCAL_ADMIN_EMAIL admin@gmail.com)";               expect_true "gmail admin email refused" grep -q 'REFUSED: LOCAL_ADMIN_EMAIL' <<<"$o"
seed_with LOCAL_ADMIN_EMAIL local-admin@trulyfreehome.com >/dev/null
o="$(seed_with TEST_CUSTOMER_PORTAL_EMAIL local-admin@trulyfreehome.com)"; expect_true "company customer email refused (even the admin address)" grep -q 'REFUSED: TEST_CUSTOMER_PORTAL_EMAIL' <<<"$o"
rm -rf "$SB"
done_tests
