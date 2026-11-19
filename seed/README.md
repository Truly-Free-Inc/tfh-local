# seed/

One-time data seed for a fresh local DB. `seed` service in docker-compose runs `run-seed.sh` after Flyway.

- Applies `sql/*.sql` in name order inside one transaction, then creates `public.tfh_local_seed_state`.
- If that marker table exists, the seed is skipped. Re-seed only with `make reset` (drops local volumes).
- **Feature flags are seeded here once and never changed.** No script updates them. Tests only read them.
- Test data only: "test test" customers, test cards, catalog rows. **No PII, no prod/stage dumps.**
- `10_feature_flags.sql` is a placeholder until the approved non-prod flag snapshot is provided.
- Catalog seeds can reuse `apps/tf-api/db-bootstrap/seeds/` (TODO: decide which of the 14 files to include).
