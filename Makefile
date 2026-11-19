# tfh-local. SAFETY first: read README.md and docs/safety.md. `up` and `verify` always run scripts/preflight.sh.
SHELL := /bin/bash
.DEFAULT_GOAL := help
export KEY BRANCH CONFIRM LOCAL_SRC REFRESH VECTOR

.PHONY: help bootstrap refresh ticket up down health logs verify status pr reset preflight check-secrets config test seed-auth prove-login prove-admin

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

health: ## core containers, one-shot jobs, tf-api /health, Mailpit, MinIO, proxy deny check
	@scripts/health.sh

seed-auth: ## (re)seed local auth users: portal test customer (tf-api DB + Kratos) and local admin (Kratos + Keto)
	@seed/auth-users.sh

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

prove-admin: ## headless staff login (Kratos browser flow) -> admin /dashboard; MODE=api needed while flag enable_admin_password_login is absent locally
	@set -a; . ./.env; set +a; node scripts/prove-admin-login.cjs
