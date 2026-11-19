# tfh-local

Local TFH stack (Docker Compose) so the team's AI can build a feature, write its test in tfh-automation on the
same ticket branch, verify everything locally (including the core gate), then open PRs. AI opens PRs; humans merge.

## SAFETY (read before anything else)
- **No production anything.** Local only. No prod hosts, credentials or data.
- **Never Syteline / Infor.** Never configured, never written. **tfhcore and Avalara are OUT.**
- **Sticky + TF: OFFLINE by default** (`EXTERNALS=offline`): no Sticky/TF values, empty egress allow-list, so
  checkout / order create / cancel / order-sync fail locally by design. `EXTERNALS=real` (later, reviewed hosts
  only) = real NON-PROD instances, TEST ORDERS ONLY. Do not touch or widen tfh-automation `lib/test-order-guard.ts`.
- **Never change feature flags** (seeded once at first DB init).
- **No secrets in git.** `.env.example` = names only. Run `make check-secrets` before every commit.
- **`scripts/preflight.sh` runs before `make up` / `make verify` and refuses** on any violation. Do not bypass it.
- App containers have **no direct internet**; egress only through an allow-list proxy (non-prod Sticky + TF only,
  empty offline) plus a fixed read-only list (`cdn.builder.io`, approved by Michael 2026-11-19).
- **AI opens PRs, never merges.**

Details: [docs/safety.md](docs/safety.md).

## Start here tonight
```bash
make bootstrap LOCAL_SRC=~/projects   # git worktrees of your clones into apps/ (never touches ~/projects/<repo>)
make up                               # preflight + build + start + health (first `next dev` compile per page ~20-30 s)
make health                           # every service + "proxy denies a non-allow-listed host"
make verify                           # core gate (@gate, not @quarantine) on the host vs the local stack, 4 workers,
                                      # no retries, 25 min cap -> .state/runs/gate-<ts>/ (make verify KEY=... adds @KEY)
make down                             # stop (volumes kept; `make reset CONFIRM=1` wipes local volumes)
```
Suite: `apps/tfh-automation` must be on a branch with `TARGET_ENV=local` (tfh-automation PR #4, `feat/local-env`)
plus `npm ci` (Playwright browsers: `npx playwright install webkit chromium firefox`).

| What | URL |
|---|---|
| Member portal | http://localhost:13001/login |
| Admin panel (staff login via funnels `/internal_admin/login`, Kratos) | http://localhost:13002 |
| Funnels (aff-landing-pages) | http://localhost:13003 |
| tf-api | http://localhost:13000/health |
| tf-apigateway | http://localhost:13004/health |
| Kratos public | http://localhost:14433 |
| Mailpit (all local mail) | http://localhost:18025 |
| MinIO console / API | http://localhost:19001 / :19000 |
| Klaviyo recorder (captured calls) | http://localhost:18090/__calls |
| Vector search (`make up VECTOR=1`) | http://localhost:18077 |

Test users (seeded by `make up` / `make seed-auth`; emails and passwords are in `.env`, never in git):
- **Portal customer "test test"**: `TEST_CUSTOMER_PORTAL_EMAIL` / `TEST_CUSTOMER_PORTAL_PASSWORD` (`make verify` passes
  them to the suite as `MEMBER_PORTAL_USER` / `MEMBER_PORTAL_PASSWORD`).
- **Local staff admin** (Kratos + Keto role `admin`): `LOCAL_ADMIN_EMAIL` / `LOCAL_ADMIN_PASSWORD`.

What is offline, and why:
- **Sticky + TF Composition API: OFFLINE** (`EXTERNALS=offline`). The stage Sticky host can't be told apart from
  prod, so no Sticky/TF values exist here and the proxy can't reach them. Checkout, order create, cancel, ship-now,
  swap and login order-sync results fail locally **by design**.
- **tfhcore, Avalara, Syteline/Infor: never configured.** Portal flows still on tfhcore (addresses, header search,
  email change, old cancel flow, token refresh) fail.
- **Klaviyo, S3, mail: local fakes** (recorder, MinIO, Mailpit). tf-api's Mailgun mail is not sent.
- **Builder.io: read-only.** Only `cdn.builder.io` is reachable (`proxy/readonly-allowlist.txt`, fixed by preflight),
  with public keys from `.env` (`LOCAL_BUILDER_PUBLIC_KEY_*`); Node apps refuse non-GET requests to it.
- **Catalog data: placeholder.** A prod-like catalog seed needs a read-only DB credential (none on this machine).
- Crons never run (`cron` profile refuses). Feature flags are seeded once, never toggled.

## Quick start
```bash
make bootstrap LOCAL_SRC=~/projects   # worktrees into apps/ (idempotent); `make refresh` fast-forwards them later
$EDITOR .env                   # created from .env.example: set APP_ENV=local, generated local passwords, ports.
                               # EXTERNALS=offline: leave every STICKY_* / TF_COMPOSITION_* EMPTY.
make up                        # preflight + build + start core services, waits for healthy, runs `make health`
make health                    # tf-api /health, Mailpit, MinIO, jobs, and a proxy-deny proof
make ticket KEY=TFHFUNNEL-1234
make verify KEY=TFHFUNNEL-1234
make pr KEY=TFHFUNNEL-1234     # dry run; CONFIRM=1 to push + open PRs
```
AI per-ticket instructions: [docs/ai-loop.md](docs/ai-loop.md). Suite env: [docs/local-env.md](docs/local-env.md). Automation merge process: [docs/automation-merge-process.md](docs/automation-merge-process.md).

## Targets
| Target | What |
|---|---|
| `make bootstrap` | Clone missing repos from `repos.yaml` into `apps/` (fresh clone by default; `LOCAL_SRC=~/projects` uses git worktrees on `tfh-local/<default_branch>`). Idempotent. |
| `make refresh` | Fetch + fast-forward clean `apps/` checkouts that are on `tfh-local/<default_branch>`; skips dirty / ticket branches. |
| `make health` | Core containers, one-shot jobs, tf-api `/health`, Mailpit UI, MinIO API + console, proxy denies a non-allow-listed host. |
| `make ticket KEY= [BRANCH=]` | Fetch every repo; check out the ticket's remote branch if it exists, else default branch; create branch `KEY` in tfh-automation. Refuses on dirty repos. Writes `.state/ticket.json`. |
| `make up` / `down` / `logs` | Preflight, then `docker compose up -d --build --wait` + health (re-run on a running stack does not recreate services); stop; follow logs (`S=tf-api`). |
| `make verify [KEY=]` | Preflight, health, `@KEY` tests (if KEY) + core gate on the host (`TARGET_ENV=local`, `VERIFY_WORKERS`=4, `VERIFY_MAX_SECONDS`=1500), test-order check. `.state/runs/<KEY or gate>-<ts>/`. |
| `make status` | Ticket, branches, dirty flags, last verify, containers. |
| `make pr KEY= [CONFIRM=1]` | Needs a green verify on the same SHAs. Push + PRs to develop (main where no develop). Never merges. |
| `make reset CONFIRM=1` | Delete local volumes only. |
| `make check-secrets`, `make config`, `make preflight` | Secret scan, compose validation, safety checks. |

## Services
| Service | State | Notes |
|---|---|---|
| postgres 17.4, redis 7.2 | wired | Mirrors tf-api's compose + `db-bootstrap` init. |
| flyway | wired | tf-api's own `Dockerfile.flyway` (apps/tf-api/flyway). |
| seed | wired (placeholder data) | One-time seed after Flyway; flags never changed afterwards. |
| tf-api | **live** | `http://localhost:13000/health`. Sticky/TF unset (offline); Redis plain (no TLS); OTEL to loopback. |
| tf-api (build) | wired | `docker/tf-api.Dockerfile` multi-stage (Go 1.24.3 build from `src/`, debian-slim runtime). |
| proxy | **live** | tinyproxy egress allow-list, default deny; empty list in offline mode. |
| ingress | wired | nginx stream; publishes ports on 127.0.0.1. |
| mailpit, minio + minio-init, klaviyo-recorder | **live** | Mailpit UI `:18025`, MinIO API `:19000` / console `:19001` (`pgsty/minio` community fork; upstream images are gone), recorder `:18090`. |
| tf-apigateway, kratos, keto, gateway-postgres | **live** | Gateway `:13004/health`; Kratos public `:14433` (admin `:14434`, loopback); Keto internal. Mirrors the gateway repo's compose; Kratos config `auth/kratos/kratos.yml` (localhost URLs, Google off, courier -> Mailpit). |
| memberportal | **live** (`next dev`) | `http://localhost:13001/login`. Points only at local tf-api. Builder.io is unreachable offline: tfh-local overlays `/login` and `/dashboard` with the portal's own LoginForm / "Dashboard Page Content" components (`docker/memberportal-overlay/`); other Builder pages fail. |
| auth users | **seeded** | `make seed-auth` (also run by `make up`): "test test" portal customer (tf-api DB + Kratos) and a local admin (Kratos, Keto role `admin`). Credentials in `.env`. `make prove-login` = headless login proof. |
| admin-panel | **live** (`next dev`) | `http://localhost:13002`. Local tf-api / gateway / Kratos only. Staff login goes through the funnels app's `/internal_admin/login` (Kratos). |
| aff-landing-pages (funnels) | **live** (`next dev`) | `http://localhost:13003`. Builder.io pages (`/`, `/offers/*`, `/info/*`, `/pages/*`) 404 offline (Builder unreachable; no allow-list entry in offline mode). Checkout needs Sticky/TF: fails offline. |
| vector-search | **live** (profile `vector`: `make up VECTOR=1`) | `http://localhost:18077`. Local data files from the repo; Vertex AI backend never configured. |
| cron | **refuses** (profile `cron`) | See [cron/README.md](cron/README.md). |

Out of scope: builderio_storefront, tfhcore, legacy repos, Avalara, Syteline/Infor.

**tfhcore note:** an audit found remaining tfhcore calls in memberportal (per-page session create, addresses,
search, logger, email change, old cancel flow, token refresh) and tf-api (cart-session fallback, Redis session
dependency, two MySQL jobs). These **will fail locally until moved to tf-api**. tfhcore is never configured here.

## Layout
`repos.yaml` app repos · `apps/` checkouts (git-ignored) · `docker/` Dockerfiles · `proxy/` egress allow-list ·
`ingress/` host ports · `klaviyo-recorder/` · `minio/` · `seed/` · `scripts/` · `safety/` host allow/deny lists ·
`cron/` · `docs/` · `.state/` tickets + verify runs (git-ignored).
