# tfh-local safety rules

These rules apply to every human and every AI using tfh-local. They are not optional and must not be
weakened to get a run green. If a rule blocks you, STOP and ask Michael.

## The rules
1. **No production anything.** No prod hosts, prod credentials, prod data or prod DB. The stack runs on your machine only.
2. **Never Syteline / Infor.** `SYTE_LINE_*`, `SYTELINE_*`, `INFOR_*` are never configured and never written to.
3. **tfhcore is OUT.** Never configure `TFH_CORE_*` / `TFHCORE_*`. **Avalara is OUT** (`AVALARA_*` unset).
4. **Sticky and TF: the shared dev/stage endpoints, TEST ORDERS ONLY** (approved by Michael 2026-11-20: "We should be using the Sticky and TF endpoints we use in dev and stage. They are the same as prod and fine to call for test orders."). Covers only Sticky (`limelightcrm.com`) and the TF Composition API dev system (`api.dev.trulyfree.com`); the prod TF API host stays denied. Every order must be a test order: customer
   first+last name "test test" and test cards (tf-api `IsTestOrder`: names both "test", or Sticky test gateway
   ids 1, 3, 7, 8, 11, 12, 14).
5. **Do not touch or widen tfh-automation `lib/test-order-guard.ts`.** No new allow-list entries, no bypass.
6. **Never change feature flags.** Flags are seeded once on first DB init (`seed/`). No script, test or AI updates them.
7. **No secrets in git.** No keys, tokens, passwords, card numbers or customer PII in this repo, logs or PR bodies.
   `.env.example` lists names only. Run `make check-secrets` before every commit.
8. **AI opens PRs, never lands them.** No merges, no approvals, no force-pushes to shared branches.
9. **Crons do not run locally** (`cron` profile refuses) until Michael decides (see `cron/README.md`).

## EXTERNALS mode (`real` is the standard setup; `offline` is the fallback)
`EXTERNALS` in `.env` selects how Sticky and the TF Composition API are handled. Preflight refuses any other value.

| Mode | What preflight requires | Effect |
|---|---|---|
| `offline` (safe fallback; empty `EXTERNALS` = offline) | Every `STICKY_*` and `TF_COMPOSITION_*` value, in `.env` **and in your shell**, is empty or a placeholder under the reserved `.invalid` TLD (e.g. `sticky.offline.invalid`); the resolved compose config agrees; the generated proxy filter (`.state/egress/allowlist.txt`) is written **empty**. | Sticky/TF calls cannot leave the machine: tf-api gets no Sticky/TF config and the proxy denies every host. `proxy/allowlist.txt` and `safety/nonprod-hosts.txt` need not be empty. Checkout, order create, cancel and login order-sync results are **expected to fail locally**. |
| `real` (**standard**, Michael 2026-11-20) | `STICKY_USERNAME`/`STICKY_PASSWORD`, `STICKY_APP_KEY` (one DNS label) and `TF_COMPOSITION_API_TOKEN` set; `STICKY_DOMAIN` a bare host; TF URL https; Sticky/TF hosts on `safety/nonprod-hosts.txt`; any prod deny-list match must be an exact literal on `safety/reviewed-exceptions.txt` (`limelightcrm.com`, `api.dev.trulyfree.com`); the derived Sticky API host (`<app key>.<STICKY_DOMAIN>`) must clear every deny pattern except those denying the reviewed `STICKY_DOMAIN` itself. | Sticky + TF dev reachable through the proxy, test orders only. Credentials come from the team's dev/stage set and are never committed. |

All other checks (Syteline/Infor, tfhcore, Avalara, `DB_HOST`, `APP_ENV`, compose scan) run in both modes. In both modes the reviewed list files (`safety/nonprod-hosts.txt`, `safety/reviewed-exceptions.txt`, `safety/prod-denylist.txt`, `proxy/allowlist.txt`, `proxy/readonly-allowlist.txt`) must have no uncommitted changes.
Never copy `STICKY_*` / `TF_COMPOSITION_*` values into `.env` while `EXTERNALS=offline`; preflight will refuse. The app key is never printed.

## How the stack enforces them
| Guard | Where | What it does |
|---|---|---|
| Preflight | `scripts/preflight.sh` (runs before `make up` and `make verify`) | `EXTERNALS=offline`: see above. `EXTERNALS=real`: refuses (exit 1) unless STICKY_DOMAIN and TF_COMPOSITION_API_BASE_URL hosts are set, match `safety/nonprod-hosts.txt` and match nothing in `safety/prod-denylist.txt` except the exact literals in `safety/reviewed-exceptions.txt`; no Syteline/Infor, tfhcore or Avalara variable is non-empty (in `.env` or your shell); DB host is the local `postgres` container; APP_ENV is not production; every `proxy/allowlist.txt` entry is non-prod. Preflight also GENERATES the effective proxy filter `.state/egress/allowlist.txt` (gitignored): empty when offline or on any refusal (fail closed), otherwise `proxy/allowlist.txt` plus the derived Sticky API host. Both modes: every pattern in the deny list, allow-lists and non-prod list must be `^...$` anchored with escaped dots (`tests/test-patterns.sh`). |
| No direct internet | `docker-compose.yml` network `internal` (`internal: true`) | App containers cannot reach the internet at all. |
| Read-only list | `proxy/readonly-allowlist.txt` | Builder.io content API (`cdn.builder.io`) only, approved by Michael 2026-11-19. Preflight refuses any entry not in its fixed `READONLY_APPROVED` set (both modes) or on the prod deny-list; Node apps refuse non-GET to it (scope below). Only public Builder keys are configured; preflight refuses any Builder private key. |
| Egress allow-list | `proxy/` (tinyproxy, `FilterDefaultDeny Yes`) | The only way out. Reads only the preflight-generated `.state/egress/allowlist.txt` (mounted read-only) plus `proxy/readonly-allowlist.txt`; `make up` recreates the proxy when it changes. Empty in offline mode (denies everything). With `EXTERNALS=real` it allows `limelightcrm.com`, the derived Sticky API host and `api.dev.trulyfree.com`. Everything else, including Klaviyo, AWS, and all prod hosts, is denied. |
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

## Never add to `proxy/allowlist.txt`, `safety/nonprod-hosts.txt` or `safety/reviewed-exceptions.txt`
Any production host (see `safety/prod-denylist.txt`; it denies every `sticky.io` / `limelightcrm.com` / `trulyfree.com`
host, including the prod TF API), Klaviyo, AWS/S3, Syteline/Infor, tfhcore, Avalara, Sentry, CloudWatch.
`safety/reviewed-exceptions.txt` holds exact literal hosts only (`^host$`, no wildcards; each must also be on
`nonprod-hosts.txt`) that may pass the deny list: today `limelightcrm.com` and `api.dev.trulyfree.com`. Any other deny
match is still refused. Changes to these files need Michael's review.

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
- `make health` proves egress. `EXTERNALS=real`: 200 for `cdn.builder.io`, `limelightcrm.com`, the derived Sticky API
  host (printed masked) and `api.dev.trulyfree.com`; 403 for everything else (prod TF API, `trulyfree.com`,
  `www`/`api.limelightcrm.com`, `sticky.io`, Klaviyo, Mailgun, Avalara, tfhcore, trulyfreehome.com, builder.io root).
  Offline: the Sticky/TF hosts must be 403 too. `make test` runs the offline shell tests in `tests/`.
