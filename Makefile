# tfh-local. SAFETY first: read README.md and docs/safety.md. `up` and `verify` always run scripts/preflight.sh.
SHELL := /bin/bash
.DEFAULT_GOAL := help
export KEY BRANCH CONFIRM LOCAL_SRC REFRESH VECTOR

.PHONY: help bootstrap refresh ticket up down health logs verify status pr reset preflight check-secrets config test seed-auth prove-login prove-admin seed-catalog seed-sitemap map-tf-products map-flag-env

help: ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

bootstrap: ## clone missing repos into apps/ (LOCAL_SRC=~/projects to use git worktrees of existing clones)
	@scripts/bootstrap.sh

refresh: ## fetch + fast-forward clean apps/ checkouts on tfh-local/<default_branch> (skips dirty/ticket branches)
	@REFRESH=1 scripts/bootstrap.sh

ticket: ## KEY=TFHFUNNEL-1234 [BRANCH=...] check out the ticket branch in every repo
	@scripts/ticket.sh

preflight: ## SAFETY checks only
	@scripts/preflight.sh

up: ## preflight, then build + start core services
	@scripts/up.sh

down: ## stop the stack (keeps volumes)
	@docker compose --profile stub --profile vector --profile cron down

warmup: ## compile the gate's next dev routes serially (also run by up and verify)
	@scripts/warmup.sh

health: ## core containers, one-shot jobs, tf-api /health, Mailpit, MinIO, proxy deny check
	@scripts/health.sh

seed-auth: ## (re)seed local auth users: portal test customer (tf-api DB + Kratos) and local admin (Kratos + Keto)
	@seed/auth-users.sh

seed-catalog: ## load the gitignored catalog export (.state/catalog-export) into LOCAL tf-api Postgres (CATALOG_MODE=replace|upsert)
	@scripts/seed-catalog.sh

map-tf-products: ## EXTERNALS=real: map local tf_products to TF DEV product ids by SKU (read-only TF lookup; also run by seed-catalog)
	@scripts/map-tf-product-ids.sh

map-flag-env: ## copy the approved production flag rows to 'development' (local tf-api APP_ENV; also run by seed-catalog)
	@scripts/map-flag-env.sh

seed-sitemap: ## generate sitemap.xml from local sitemap_entries via local tf-api -> local MinIO (served by funnels /sitemap.xml)
	@scripts/seed-sitemap.sh

prove-login: ## headless portal login as the seeded test customer -> /dashboard; screenshot .state/m2-login.png
	@set -a; . ./.env; set +a; node scripts/prove-portal-login.cjs

logs: ## follow logs (S=service to filter)
	@docker compose logs -f --tail=200 $(S)

verify: ## [KEY=...] preflight, health, (ticket tests) + core gate on host (TARGET_ENV=local), test-order check
	@scripts/verify.sh

status: ## ticket, branches, dirty flags, last verify, containers
	@scripts/status.sh

pr: ## KEY=... [CONFIRM=1] dry-run by default; push + open PRs (never lands them)
	@scripts/pr.sh

reset: ## CONFIRM=1 delete LOCAL volumes only
	@scripts/reset.sh

test: ## run the shell tests in tests/ (no network; sandbox copies + dummy env only)
	@set -e; for t in tests/test-*.sh; do bash "$$t"; done

check-secrets: ## scan this repo for secrets (run before every commit)
	@scripts/check-no-secrets.sh

config: ## validate docker-compose.yml
	@docker compose config -q && echo "compose config: OK"

prove-admin: ## headless staff login: funnels /internal_admin/login form (Kratos) -> admin /dashboard; MODE=api skips the form
	@set -a; . ./.env; set +a; node scripts/prove-admin-login.cjs
