# tfh-local

Local TFH stack (Docker Compose) so the team's AI can build a feature, write its test in tfh-automation on the
same ticket branch, verify everything locally (including the core gate), then open PRs. AI opens PRs; humans merge.

## SAFETY (read before anything else)
- **No production anything.** Local only. No prod hosts, credentials or data.
- **Never Syteline / Infor.** Never configured, never written. **tfhcore and Avalara are OUT.**
- **Sticky + TF: real NON-PROD instances, TEST ORDERS ONLY** ("test test" + test cards). Do not touch or widen
  tfh-automation `lib/test-order-guard.ts`.
- **Never change feature flags** (seeded once at first DB init).
- **No secrets in git.** `.env.example` = names only. Run `make check-secrets` before every commit.
- **`scripts/preflight.sh` runs before `make up` / `make verify` and refuses** on any violation. Do not bypass it.
- App containers have **no direct internet**; egress only through an allow-list proxy (non-prod Sticky + TF only).
- **AI opens PRs, never merges.**

Details: [docs/safety.md](docs/safety.md).

## Quick start
```bash
make bootstrap                 # clone repos into apps/ (LOCAL_SRC=~/projects to use git worktrees of your clones)
$EDITOR .env                   # NON-PROD values from the secrets manager; add the non-prod hosts to
                               # safety/nonprod-hosts.txt and proxy/allowlist.txt (reviewed)
make up                        # preflight + build + start core services
make ticket KEY=TFHFUNNEL-1234
make verify KEY=TFHFUNNEL-1234
make pr KEY=TFHFUNNEL-1234     # dry run; CONFIRM=1 to push + open PRs
```
AI per-ticket instructions: [docs/ai-loop.md](docs/ai-loop.md). Suite env: [docs/local-env.md](docs/local-env.md).

## Targets
| Target | What |
|---|---|
| `make bootstrap` | Clone missing repos from `repos.yaml` into `apps/` (fresh clone by default; `LOCAL_SRC=~/projects` uses git worktrees). |
| `make ticket KEY= [BRANCH=]` | Fetch every repo; check out the ticket's remote branch if it exists, else default branch; create branch `KEY` in tfh-automation. Refuses on dirty repos. Writes `.state/ticket.json`. |
| `make up` / `down` / `logs` | Preflight, then `docker compose up -d --build`; stop; follow logs (`S=tf-api`). |
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
| tf-api | wired | `docker/tf-api.Dockerfile` multi-stage (Go 1.24.3 build from `src/`, debian-slim runtime). |
| proxy | wired | tinyproxy egress allow-list, default deny. |
| ingress | wired | nginx stream; publishes ports on 127.0.0.1. |
| mailpit, minio + minio-init, klaviyo-recorder | wired | Local fakes for mail, S3, Klaviyo. |
| memberportal, tf-apigateway, kratos, keto, gateway-postgres, admin-panel, aff-landing-pages | **stub** (profile `stub`) | TODO in docker-compose.yml. |
| vector-search | **stub** (profile `vector`) | POC; TODO Dockerfile. |
| cron | **refuses** (profile `cron`) | See [cron/README.md](cron/README.md). |

Out of scope: builderio_storefront, tfhcore, legacy repos, Avalara, Syteline/Infor.

**tfhcore note:** an audit found remaining tfhcore calls in memberportal (per-page session create, addresses,
search, logger, email change, old cancel flow, token refresh) and tf-api (cart-session fallback, Redis session
dependency, two MySQL jobs). These **will fail locally until moved to tf-api**. tfhcore is never configured here.

## Layout
`repos.yaml` app repos · `apps/` checkouts (git-ignored) · `docker/` Dockerfiles · `proxy/` egress allow-list ·
`ingress/` host ports · `klaviyo-recorder/` · `minio/` · `seed/` · `scripts/` · `safety/` host allow/deny lists ·
`cron/` · `docs/` · `.state/` tickets + verify runs (git-ignored).
