-- PLACEHOLDER: feature-flag seed for tfh-local.
-- Values must come from a read-only export of the non-prod (stage) flag values, reviewed before commit.
-- Applied ONCE on first DB init by seed/run-seed.sh. NEVER change feature flags afterwards (no script,
-- no test, no AI may UPDATE/INSERT/DELETE feature_flags on a running stack).
-- The approved prod snapshot (Michael, 2026-11-19 4:59 PM ET) is loaded by `make seed-catalog` (seed/catalog/load.sql),
-- not here. Nothing else may change flags.
SELECT 1;
