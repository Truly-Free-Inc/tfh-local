# tfh-local safety rules

These rules apply to every human and every AI using tfh-local. They are not optional and must not be
weakened to get a run green. If a rule blocks you, STOP and ask Michael.

## The rules
1. **No production anything.** No prod hosts, prod credentials, prod data or prod DB. The stack runs on your machine only.
2. **Never Syteline / Infor.** `SYTE_LINE_*`, `SYTELINE_*`, `INFOR_*` are never configured and never written to.
3. **tfhcore is OUT.** Never configure `TFH_CORE_*` / `TFHCORE_*`. **Avalara is OUT** (`AVALARA_*` unset).
4. **Sticky and TF: real NON-PROD instances, TEST ORDERS ONLY.** Every order must be a test order: customer
   first+last name "test test" and test cards (tf-api `IsTestOrder`: names both "test", or Sticky test gateway
   ids 1, 3, 7, 8, 11, 12, 14).
5. **Do not touch or widen tfh-automation `lib/test-order-guard.ts`.** No new allow-list entries, no bypass.
6. **Never change feature flags.** Flags are seeded once on first DB init (`seed/`). No script, test or AI updates them.
7. **No secrets in git.** No keys, tokens, passwords, card numbers or customer PII in this repo, logs or PR bodies.
   `.env.example` lists names only. Run `make check-secrets` before every commit.
8. **AI opens PRs, never lands them.** No merges, no approvals, no force-pushes to shared branches.
9. **Crons do not run locally** (`cron` profile refuses) until Michael decides (see `cron/README.md`).

## How the stack enforces them
| Guard | Where | What it does |
|---|---|---|
| Preflight | `scripts/preflight.sh` (runs before `make up` and `make verify`) | Refuses (exit 1) unless STICKY_DOMAIN and TF_COMPOSITION_API_BASE_URL hosts are set, match `safety/nonprod-hosts.txt` and match nothing in `safety/prod-denylist.txt`; no Syteline/Infor, tfhcore or Avalara variable is non-empty (in `.env` or your shell); DB host is the local `postgres` container; APP_ENV is not production; every `proxy/allowlist.txt` entry is non-prod. |
| No direct internet | `docker-compose.yml` network `internal` (`internal: true`) | App containers cannot reach the internet at all. |
| Egress allow-list | `proxy/` (tinyproxy, `FilterDefaultDeny Yes`) | The only way out. Allows just the hosts in `proxy/allowlist.txt` (non-prod Sticky + TF). Everything else, including Klaviyo, AWS, and all prod hosts, is denied. |
| Build vs runtime | | Image builds use the Docker daemon's network, so Go modules / Docker Hub / apt work at build time. Running containers never get that network. |
| Host ports | `ingress` (nginx stream) | Publishes service ports on 127.0.0.1 only (non-default ports). |
| Test-order check | `scripts/check-test-orders.sh` (runs in `make verify`) | Read-only query of the local DB: every order created since the run started must be a test order, or verify fails. |
| Fakes | MinIO (S3), Klaviyo recorder, Mailpit | No real S3, Klaviyo or outbound mail. |
| Secret scan | `scripts/check-no-secrets.sh` | Greps the repo for key/token/card patterns; `.env` and `apps/` must never be tracked. |

## Never add to `proxy/allowlist.txt` or `safety/nonprod-hosts.txt`
Any production host (see `safety/prod-denylist.txt`), Klaviyo, AWS/S3, Syteline/Infor, tfhcore, Avalara,
Sentry, CloudWatch. Changes to these two files need Michael's review.

## If something looks wrong
A non-test order, a prod host in a log, a flag that changed, a secret in output: **STOP**, do not retry, do
not clean up on your own, report to Michael with the run directory (`.state/runs/...`).
