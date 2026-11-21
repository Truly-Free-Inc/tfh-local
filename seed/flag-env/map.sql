-- make map-flag-env (also run by make seed-catalog): give local tf-api's environment-scoped flag lookups the
-- PRODUCTION snapshot values (TFHFUNNEL-8090).
--
-- tf-api reads flags with GetFeatureFlagByName(name, APP_ENV). The approved snapshot only has 'production' rows,
-- and validate_environment_trigger rejects 'local', so with APP_ENV=local every such lookup missed and read as
-- disabled (e.g. tf_order_type_enabled -> 400 TF_ORDER_TYPE_DISABLED). tfh-local runs tf-api with
-- APP_ENV=development (TF_API_APP_ENV, what develop runs) and this file makes the 'development' rows an exact copy
-- of the 'production' rows. 'development' passes the trigger. Rows are only DERIVED from the snapshot already in
-- the local DB; no value is invented, no other environment is touched. Idempotent. Local container only.
\set ON_ERROR_STOP 1
BEGIN;
DO $$
BEGIN
  IF inet_server_addr() IS NOT NULL AND NOT (inet_server_addr() << '127.0.0.0/8'::inet OR inet_server_addr() << '10.0.0.0/8'::inet
     OR inet_server_addr() << '172.16.0.0/12'::inet OR inet_server_addr() << '192.168.0.0/16'::inet OR inet_server_addr() = '::1'::inet) THEN
    RAISE EXCEPTION 'map-flag-env: refusing a non-local database server';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE environment = 'production') THEN
    RAISE EXCEPTION 'map-flag-env: no production rows (load the snapshot first: make seed-catalog)';
  END IF;
END $$;
DELETE FROM public.feature_flags WHERE environment = 'development';
INSERT INTO public.feature_flags (name, description, environment, enabled, metadata, metadata_arbitrary,
                                  application_scope, created_at, updated_at, created_by, updated_by)
SELECT name, description, 'development', enabled, metadata, metadata_arbitrary,
       application_scope, now(), now(), 'tfh-local map-flag-env', 'tfh-local map-flag-env'
  FROM public.feature_flags WHERE environment = 'production' ORDER BY id;
-- Self-check: the two sets must now be identical.
DO $$
DECLARE d int;
BEGIN
  SELECT count(*) INTO d FROM (
    (SELECT name, enabled, metadata, metadata_arbitrary, application_scope FROM public.feature_flags WHERE environment = 'production'
     EXCEPT ALL
     SELECT name, enabled, metadata, metadata_arbitrary, application_scope FROM public.feature_flags WHERE environment = 'development')
    UNION ALL
    (SELECT name, enabled, metadata, metadata_arbitrary, application_scope FROM public.feature_flags WHERE environment = 'development'
     EXCEPT ALL
     SELECT name, enabled, metadata, metadata_arbitrary, application_scope FROM public.feature_flags WHERE environment = 'production')) x;
  IF d <> 0 THEN RAISE EXCEPTION 'map-flag-env: development rows differ from production (% rows)', d; END IF;
END $$;
SELECT 'map-flag-env: development rows = ' || count(*) || ' (copied from production)' FROM public.feature_flags WHERE environment = 'development';
COMMIT;
