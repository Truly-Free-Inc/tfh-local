#!/usr/bin/env bash
# Scan tracked + staged files in THIS repo for things that look like secrets. Run before every commit.
# Exits 1 on any hit. False positive? Rephrase the text; do not add allow-list exceptions for real values.
. "$(dirname "$0")/lib.sh"
cd "$ROOT"
files="$( { git ls-files; git diff --cached --name-only; git ls-files --others --exclude-standard; } | sort -u )"
[ -n "$files" ] || { grn "check-no-secrets: no files"; exit 0; }

PATTERNS=(
  'AKIA[0-9A-Z]{16}'                                  # AWS access key id
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'                # private keys
  'xox[baprs]-[0-9A-Za-z-]{10,}'                      # Slack tokens
  'gh[pousr]_[0-9A-Za-z]{30,}'                        # GitHub tokens
  'pk_[0-9a-f]{30,}'                                  # Klaviyo private keys
  'sk_(live|test)_[0-9A-Za-z]{16,}'                   # Stripe-style keys
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'    # JWTs
  '\b[3-6][0-9]{3}[ -]?[0-9]{4}[ -]?[0-9]{4}[ -]?[0-9]{4}\b'  # card-like numbers
  '://[^/[:space:]:@]+:[^/[:space:]@]{6,}@'           # credentials in URLs
)
hits=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in scripts/check-no-secrets.sh) continue ;; esac
  for p in "${PATTERNS[@]}"; do
    if grep -nEI -e "$p" "$f" >/dev/null 2>&1; then
      red "possible secret in $f (pattern: $p)"; grep -nEI -e "$p" "$f" | cut -c1-120 >&2; hits=1
    fi
  done
  # .env.example must have names only (empty values).
  if [ "$f" = ".env.example" ] && grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.+' "$f" >/dev/null; then
    red ".env.example has values; it must list NAMES only"; grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.+' "$f" >&2; hits=1
  fi
done <<< "$files"
# Never commit these.
git ls-files --error-unmatch .env >/dev/null 2>&1 && { red ".env is tracked!"; hits=1; }
git ls-files | grep -qE '^apps/' && { red "apps/ is tracked!"; hits=1; }
# gitleaks (if installed; `brew install gitleaks`): full committed history + staged changes, redacted output.
# CI runs it on every PR (.github/workflows/gitleaks.yml), so a missing local binary is a warning, not a pass.
if [ "${SKIP_GITLEAKS:-0}" != "1" ]; then
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks git --config "$ROOT/.gitleaks.toml" --redact --no-banner --log-level warn --exit-code 1 "$ROOT" \
      || { red "gitleaks: leaks in git history (see above; values redacted)"; hits=1; }
    gitleaks git --pre-commit --staged --config "$ROOT/.gitleaks.toml" --redact --no-banner --log-level warn --exit-code 1 "$ROOT" \
      || { red "gitleaks: leaks in staged changes"; hits=1; }
  else
    ylw "gitleaks not installed (brew install gitleaks); ran the built-in patterns only. CI runs gitleaks on PRs."
  fi
fi
[ "$hits" -eq 0 ] || { red "check-no-secrets: FAILED"; exit 1; }
grn "check-no-secrets: OK"
