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
- App containers have **no direct internet**; egress only through an allow-list proxy (non-prod Sticky + TF only).
- **AI opens PRs, never merges.**

Details: [docs/safety.md](docs/safety.md).

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
| `make verify KEY=` | Preflight, health, `@KEY` tests + core gate on the host, test-order check. `.state/runs/<KEY>-<ts>/`. |
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
