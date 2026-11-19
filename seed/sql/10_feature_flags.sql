-- PLACEHOLDER: feature-flag seed for tfh-local.
-- Values must come from a read-only export of the non-prod (stage) flag values, reviewed before commit.
-- Applied ONCE on first DB init by seed/run-seed.sh. NEVER change feature flags afterwards (no script,
-- no test, no AI may UPDATE/INSERT/DELETE feature_flags on a running stack).
-- TODO(Richard/Michael): provide the approved flag snapshot (names + enabled + environment only; no PII).
SELECT 1;
