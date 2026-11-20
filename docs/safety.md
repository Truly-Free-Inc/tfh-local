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

## EXTERNALS mode (offline by default)
`EXTERNALS` in `.env` selects how Sticky and the TF Composition API are handled. Preflight refuses any other value.

| Mode | What preflight requires | Effect |
|---|---|---|
| `offline` (**default**; empty `EXTERNALS` = offline) | Every `STICKY_*` and `TF_COMPOSITION_*` value, in `.env` **and in your shell**, is empty or a placeholder under the reserved `.invalid` TLD (e.g. `sticky.offline.invalid`); the resolved compose config agrees; `proxy/allowlist.txt` has **zero** entries; `safety/nonprod-hosts.txt` has no entries and neither file has uncommitted changes. | Sticky/TF calls cannot leave the machine: tf-api gets no Sticky/TF config and the proxy denies every host. Checkout, order create, cancel and login order-sync results are **expected to fail locally**. |
| `real` | Exactly the checks below (non-prod Sticky/TF hosts on `safety/nonprod-hosts.txt`, not on the prod deny-list, every allow-list entry non-prod). | Non-prod Sticky/TF reachable through the proxy, test orders only. Needs reviewed hosts; not in use yet. |

All other checks (Syteline/Infor, tfhcore, Avalara, `DB_HOST`, `APP_ENV`, compose scan) run in both modes.
Never copy real `STICKY_*` / `TF_COMPOSITION_*` values into `.env` while `EXTERNALS=offline`; preflight will refuse.

## How the stack enforces them
| Guard | Where | What it does |
|---|---|---|
| Preflight | `scripts/preflight.sh` (runs before `make up` and `make verify`) | `EXTERNALS=offline`: see above. `EXTERNALS=real`: refuses (exit 1) unless STICKY_DOMAIN and TF_COMPOSITION_API_BASE_URL hosts are set, match `safety/nonprod-hosts.txt` and match nothing in `safety/prod-denylist.txt`; no Syteline/Infor, tfhcore or Avalara variable is non-empty (in `.env` or your shell); DB host is the local `postgres` container; APP_ENV is not production; every `proxy/allowlist.txt` entry is non-prod. Both modes: every pattern in the deny list, allow-lists and non-prod list must be `^...$` anchored with escaped dots (`tests/test-patterns.sh`). |
| No direct internet | `docker-compose.yml` network `internal` (`internal: true`) | App containers cannot reach the internet at all. |
| Read-only list | `proxy/readonly-allowlist.txt` | Builder.io content API (`cdn.builder.io`) only, approved by Michael 2026-11-19. Preflight refuses any entry not in its fixed `READONLY_APPROVED` set (both modes) or on the prod deny-list; Node apps refuse non-GET to it (scope below). Only public Builder keys are configured; preflight refuses any Builder private key. |
| Egress allow-list | `proxy/` (tinyproxy, `FilterDefaultDeny Yes`) | The only way out. Empty in offline mode (denies everything; `make health` proves a denied request). Allows just the hosts in `proxy/allowlist.txt` (non-prod Sticky + TF). Everything else, including Klaviyo, AWS, and all prod hosts, is denied. |
| Build vs runtime | | Image builds use the Docker daemon's network, so Go modules / Docker Hub / apt work at build time. Running containers never get that network. |
| Host ports | `ingress` (nginx stream) | Publishes service ports on 127.0.0.1 only (non-default ports). |
| Test-order check | `scripts/check-test-orders.sh` (runs in `make verify`) | Read-only query of the local DB: every order created since the run started must be a test order, or verify fails. |
| Fakes | MinIO (S3), Klaviyo recorder, Mailpit | No real S3, Klaviyo or outbound mail. |
| Secret scan | `scripts/check-no-secrets.sh` | Greps the repo for key/token/card patterns; `.env` and `apps/` must never be tracked. |

## Scope of the Builder.io read-only (GET-only) rule
- **The proxy allow-list is the real egress boundary.** It decides which *hosts* can be reached at all (default deny).
  For HTTPS it only sees a `CONNECT cdn.builder.io:443` tunnel, so it **cannot** tell GET from POST.
- The GET/HEAD/OPTIONS-only rule is enforced by `docker/node-egress-preload.cjs`, and **only for Node's global
  `fetch` / undici** in the containers that load it (memberportal, aff-landing-pages). It does **not** cover Node's
  `http`/`https` modules (or libraries built on them, e.g. axios), other runtimes, or **browsers** (a browser on the
  host talks to `cdn.builder.io` directly, outside the proxy).
- Next.js **middleware** runs in the edge-runtime sandbox, whose bundled fetch cannot see the global dispatcher. The
  preload hands that sandbox the guarded Node fetch (same proxy, same GET-only rule), so middleware fetches such as
  the storefront's Builder `url-redirects` rules work locally. Requests whose body or signal cannot cross the
  sandbox boundary keep the sandbox fetch, which has no route out of the `internal` network (fails closed).
- What keeps Builder read-only overall: only `cdn.builder.io` (the public content CDN) is allowed, never `builder.io`
  or its write/admin API hosts (`make health` proves `builder.io` is denied); only *public* API keys are configured,
  and preflight refuses `BUILDER_PRIVATE_KEY`-style variables and any `bpk-` value.
- `make health` asserts the preload reports `ACTIVE` in each of those containers (it logs `[tfh-local egress-guard]
  ACTIVE|INACTIVE` once at start). If it is INACTIVE, server-side fetch has no proxy and fails closed (offline).

## Never add to `proxy/allowlist.txt` or `safety/nonprod-hosts.txt`
Any production host (see `safety/prod-denylist.txt`), Klaviyo, AWS/S3, Syteline/Infor, tfhcore, Avalara,
Sentry, CloudWatch. Changes to these two files need Michael's review.

## If something looks wrong
A non-test order, a prod host in a log, a flag that changed, a secret in output: **STOP**, do not retry, do
not clean up on your own, report to Michael with the run directory (`.state/runs/...`).

## Hardening checks (M5h)
- Deny/allow pattern files must be `^...$` anchored with escaped dots (preflight refuses otherwise). Prod TFH
  domains are denied by suffix; named internal hosts belong only in the gitignored `safety/prod-denylist.local.txt`.
  Git history before this change still contains some named hosts (history is never rewritten).
- `make pr` pushes only via `safe_push` (never main/master/develop/stage/the PR base).
- Compose credentials have no defaults; `make bootstrap` generates missing ones into `.env` (never printed).
- `make check-secrets` runs gitleaks (full history + staged) when installed; CI runs it on every PR.
- `make health` proves egress: 403 for prod/Sticky/Klaviyo/Mailgun/Avalara/tfhcore/builder.io root, 200 only for
  the read-only allow-list. `make test` runs the offline shell tests in `tests/`.
