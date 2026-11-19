-- Catalog loader (run via `make seed-catalog`). Catalog-only export from prod tf-api replica (Cerebro, nextgen_datastream_public).
-- First run locally 2026-11-19 (74 tables, exported == loaded). Loads ONLY the allow-listed tables in data/*.json (see ALLOWLIST.md / REPORT.md).
-- Never touches feature_flags, customers, orders, subscriptions, internal_users, or any other table.
--
-- Run from THIS directory with a psql that can read these files (the \set backticks run `cat` on the psql
-- client host), e.g. from the host against the local Postgres port:
--   cd ~/projects/tfh-local/.state/catalog-export && PGHOST=localhost PGPORT=<local pg port> PGUSER=... PGDATABASE=... \
--     psql -v ON_ERROR_STOP=1 -v mode=replace -f load.sql
-- or `docker compose cp .state/catalog-export postgres:/tmp/catalog-export` then psql -f inside /tmp/catalog-export.
-- Refuse if the target looks remote: the guard below aborts unless inet_server_addr() is local/private/NULL(socket).
--
-- mode=replace (default): inside ONE transaction, DELETE allow-listed tables in reverse FK order, then INSERT in FK
--   order. If any non-catalog row (test order, cart, subscription...) references a catalog row, the DELETE fails and
--   the whole load rolls back: report it, do not add CASCADE.
-- mode=upsert: INSERT ... ON CONFLICT (id) DO UPDATE (tables with id) / DO NOTHING (join tables); keeps local rows.
--
-- Data quirks handled: Datastream stores json/jsonb as JSON *strings* -> re-parsed for json/jsonb target columns;
-- generated columns skipped; search_vector skipped (rebuilt by local triggers on insert); local-only columns
-- (sticky_offers.delivery_model_id/order_plan_id, campaign_products.variant_id, campaigns.created_by) stay NULL;
-- sequences are bumped to max(id) after load.
\set ON_ERROR_STOP on
\if :{?mode}
\else
  \set mode replace
\endif
DO $$ BEGIN
  IF inet_server_addr() IS NOT NULL AND NOT (inet_server_addr() << '127.0.0.0/8' OR inet_server_addr() << '10.0.0.0/8'
     OR inet_server_addr() << '172.16.0.0/12' OR inet_server_addr() << '192.168.0.0/16' OR inet_server_addr() = '::1') THEN
    RAISE EXCEPTION 'catalog loader: refusing non-local server %', inet_server_addr();
  END IF;
END $$;
BEGIN;
CREATE TEMP TABLE _catalog_stage (ord int PRIMARY KEY, tbl text NOT NULL UNIQUE, rows jsonb NOT NULL) ON COMMIT DROP;

\set j `cat data/campaigns.json`
INSERT INTO _catalog_stage VALUES (1, 'campaigns', :'j'::jsonb);  -- 8 rows
\set j `cat data/categories.json`
INSERT INTO _catalog_stage VALUES (2, 'categories', :'j'::jsonb);  -- 21 rows
\set j `cat data/sticky_products.json`
INSERT INTO _catalog_stage VALUES (3, 'sticky_products', :'j'::jsonb);  -- 679 rows
\set j `cat data/campaign_products.json`
INSERT INTO _catalog_stage VALUES (4, 'campaign_products', :'j'::jsonb);  -- 55 rows
\set j `cat data/cancellation_prompts.json`
INSERT INTO _catalog_stage VALUES (5, 'cancellation_prompts', :'j'::jsonb);  -- 1 rows
\set j `cat data/cancellation_reasons.json`
INSERT INTO _catalog_stage VALUES (6, 'cancellation_reasons', :'j'::jsonb);  -- 8 rows
\set j `cat data/cancellation_prompt_reasons.json`
INSERT INTO _catalog_stage VALUES (7, 'cancellation_prompt_reasons', :'j'::jsonb);  -- 8 rows
\set j `cat data/coupons.json`
INSERT INTO _catalog_stage VALUES (8, 'coupons', :'j'::jsonb);  -- 43 rows
\set j `cat data/sticky_billing_models.json`
INSERT INTO _catalog_stage VALUES (9, 'sticky_billing_models', :'j'::jsonb);  -- 7 rows
\set j `cat data/coupon_allowed_billing_models.json`
INSERT INTO _catalog_stage VALUES (10, 'coupon_allowed_billing_models', :'j'::jsonb);  -- 12 rows
\set j `cat data/coupon_products.json`
INSERT INTO _catalog_stage VALUES (11, 'coupon_products', :'j'::jsonb);  -- 729 rows
\set j `cat data/rule_definitions.json`
INSERT INTO _catalog_stage VALUES (12, 'rule_definitions', :'j'::jsonb);  -- 2 rows
\set j `cat data/coupon_rules.json`
INSERT INTO _catalog_stage VALUES (13, 'coupon_rules', :'j'::jsonb);  -- 1 rows
\set j `cat data/icons.json`
INSERT INTO _catalog_stage VALUES (14, 'icons', :'j'::jsonb);  -- 45 rows
\set j `cat data/images.json`
INSERT INTO _catalog_stage VALUES (15, 'images', :'j'::jsonb);  -- 1381 rows
\set j `cat data/ingredients.json`
INSERT INTO _catalog_stage VALUES (16, 'ingredients', :'j'::jsonb);  -- 241 rows
\set j `cat data/sticky_offers.json`
INSERT INTO _catalog_stage VALUES (17, 'sticky_offers', :'j'::jsonb);  -- 1382 rows
\set j `cat data/offer_billing_model_overrides.json`
INSERT INTO _catalog_stage VALUES (18, 'offer_billing_model_overrides', :'j'::jsonb);  -- 8 rows
\set j `cat data/upsell_flows.json`
INSERT INTO _catalog_stage VALUES (19, 'upsell_flows', :'j'::jsonb);  -- 63 rows
\set j `cat data/offer_dropoff_upsell_flows.json`
INSERT INTO _catalog_stage VALUES (20, 'offer_dropoff_upsell_flows', :'j'::jsonb);  -- 108 rows
\set j `cat data/offer_faqs.json`
INSERT INTO _catalog_stage VALUES (21, 'offer_faqs', :'j'::jsonb);  -- 127 rows
\set j `cat data/offer_highlights.json`
INSERT INTO _catalog_stage VALUES (22, 'offer_highlights', :'j'::jsonb);  -- 515 rows
\set j `cat data/offer_images.json`
INSERT INTO _catalog_stage VALUES (23, 'offer_images', :'j'::jsonb);  -- 47 rows
\set j `cat data/offer_page_placements.json`
INSERT INTO _catalog_stage VALUES (24, 'offer_page_placements', :'j'::jsonb);  -- 1649 rows
\set j `cat data/payment_methods.json`
INSERT INTO _catalog_stage VALUES (25, 'payment_methods', :'j'::jsonb);  -- 6 rows
\set j `cat data/offer_payment_methods.json`
INSERT INTO _catalog_stage VALUES (26, 'offer_payment_methods', :'j'::jsonb);  -- 853 rows
\set j `cat data/offer_product_operations.json`
INSERT INTO _catalog_stage VALUES (27, 'offer_product_operations', :'j'::jsonb);  -- 9 rows
\set j `cat data/sticky_offer_products.json`
INSERT INTO _catalog_stage VALUES (28, 'sticky_offer_products', :'j'::jsonb);  -- 10293 rows
\set j `cat data/offer_product_operation_sources.json`
INSERT INTO _catalog_stage VALUES (29, 'offer_product_operation_sources', :'j'::jsonb);  -- 12 rows
\set j `cat data/offer_product_operation_targets.json`
INSERT INTO _catalog_stage VALUES (30, 'offer_product_operation_targets', :'j'::jsonb);  -- 12 rows
\set j `cat data/refills.json`
INSERT INTO _catalog_stage VALUES (31, 'refills', :'j'::jsonb);  -- 5 rows
\set j `cat data/offer_refills.json`
INSERT INTO _catalog_stage VALUES (32, 'offer_refills', :'j'::jsonb);  -- 5 rows
\set j `cat data/size_options.json`
INSERT INTO _catalog_stage VALUES (33, 'size_options', :'j'::jsonb);  -- 2 rows
\set j `cat data/offer_size_options.json`
INSERT INTO _catalog_stage VALUES (34, 'offer_size_options', :'j'::jsonb);  -- 2 rows
\set j `cat data/tags.json`
INSERT INTO _catalog_stage VALUES (35, 'tags', :'j'::jsonb);  -- 22 rows
\set j `cat data/offer_tags.json`
INSERT INTO _catalog_stage VALUES (36, 'offer_tags', :'j'::jsonb);  -- 47 rows
\set j `cat data/offer_upsell_flows.json`
INSERT INTO _catalog_stage VALUES (37, 'offer_upsell_flows', :'j'::jsonb);  -- 8 rows
\set j `cat data/offer_urls.json`
INSERT INTO _catalog_stage VALUES (38, 'offer_urls', :'j'::jsonb);  -- 7 rows
\set j `cat data/offer_why_you_love_it_icons.json`
INSERT INTO _catalog_stage VALUES (39, 'offer_why_you_love_it_icons', :'j'::jsonb);  -- 65 rows
\set j `cat data/order_bump_configurations.json`
INSERT INTO _catalog_stage VALUES (40, 'order_bump_configurations', :'j'::jsonb);  -- 2 rows
\set j `cat data/order_bump_configuration_items.json`
INSERT INTO _catalog_stage VALUES (41, 'order_bump_configuration_items', :'j'::jsonb);  -- 4 rows
\set j `cat data/post_trial_offer_billings.json`
INSERT INTO _catalog_stage VALUES (42, 'post_trial_offer_billings', :'j'::jsonb);  -- 100 rows
\set j `cat data/product_before_afters.json`
INSERT INTO _catalog_stage VALUES (43, 'product_before_afters', :'j'::jsonb);  -- 59 rows
\set j `cat data/product_collections.json`
INSERT INTO _catalog_stage VALUES (44, 'product_collections', :'j'::jsonb);  -- 1 rows
\set j `cat data/product_collection_items.json`
INSERT INTO _catalog_stage VALUES (45, 'product_collection_items', :'j'::jsonb);  -- 19 rows
\set j `cat data/product_details.json`
INSERT INTO _catalog_stage VALUES (46, 'product_details', :'j'::jsonb);  -- 92 rows
\set j `cat data/product_excluded_ingredients.json`
INSERT INTO _catalog_stage VALUES (47, 'product_excluded_ingredients', :'j'::jsonb);  -- 683 rows
\set j `cat data/product_faqs.json`
INSERT INTO _catalog_stage VALUES (48, 'product_faqs', :'j'::jsonb);  -- 673 rows
\set j `cat data/product_recommendations.json`
INSERT INTO _catalog_stage VALUES (49, 'product_recommendations', :'j'::jsonb);  -- 278 rows
\set j `cat data/product_refill_data.json`
INSERT INTO _catalog_stage VALUES (50, 'product_refill_data', :'j'::jsonb);  -- 26 rows
\set j `cat data/product_refill_faqs.json`
INSERT INTO _catalog_stage VALUES (51, 'product_refill_faqs', :'j'::jsonb);  -- 21 rows
\set j `cat data/product_refill_images.json`
INSERT INTO _catalog_stage VALUES (52, 'product_refill_images', :'j'::jsonb);  -- 24 rows
\set j `cat data/product_tags.json`
INSERT INTO _catalog_stage VALUES (53, 'product_tags', :'j'::jsonb);  -- 229 rows
\set j `cat data/product_variations.json`
INSERT INTO _catalog_stage VALUES (54, 'product_variations', :'j'::jsonb);  -- 19 rows
\set j `cat data/product_why_you_love_it_icons.json`
INSERT INTO _catalog_stage VALUES (55, 'product_why_you_love_it_icons', :'j'::jsonb);  -- 290 rows
\set j `cat data/promo_codes.json`
INSERT INTO _catalog_stage VALUES (56, 'promo_codes', :'j'::jsonb);  -- 43 rows
\set j `cat data/volume_discounts.json`
INSERT INTO _catalog_stage VALUES (57, 'volume_discounts', :'j'::jsonb);  -- 1 rows
\set j `cat data/promotions.json`
INSERT INTO _catalog_stage VALUES (58, 'promotions', :'j'::jsonb);  -- 1 rows
\set j `cat data/promotion_products.json`
INSERT INTO _catalog_stage VALUES (59, 'promotion_products', :'j'::jsonb);  -- 36 rows
\set j `cat data/sitemap_entries.json`
INSERT INTO _catalog_stage VALUES (60, 'sitemap_entries', :'j'::jsonb);  -- 418 rows
\set j `cat data/sticky_child_products.json`
INSERT INTO _catalog_stage VALUES (61, 'sticky_child_products', :'j'::jsonb);  -- 112 rows
\set j `cat data/sticky_product_add_ons.json`
INSERT INTO _catalog_stage VALUES (62, 'sticky_product_add_ons', :'j'::jsonb);  -- 441 rows
\set j `cat data/sticky_product_images.json`
INSERT INTO _catalog_stage VALUES (63, 'sticky_product_images', :'j'::jsonb);  -- 323 rows
\set j `cat data/sticky_product_ingredients.json`
INSERT INTO _catalog_stage VALUES (64, 'sticky_product_ingredients', :'j'::jsonb);  -- 551 rows
\set j `cat data/sticky_shippings.json`
INSERT INTO _catalog_stage VALUES (65, 'sticky_shippings', :'j'::jsonb);  -- 5 rows
\set j `cat data/tf_products.json`
INSERT INTO _catalog_stage VALUES (66, 'tf_products', :'j'::jsonb);  -- 679 rows
\set j `cat data/upsell_flow_items.json`
INSERT INTO _catalog_stage VALUES (67, 'upsell_flow_items', :'j'::jsonb);  -- 137 rows
\set j `cat data/upsell_flow_variants.json`
INSERT INTO _catalog_stage VALUES (68, 'upsell_flow_variants', :'j'::jsonb);  -- 50 rows
\set j `cat data/upsell_flow_step_experiments.json`
INSERT INTO _catalog_stage VALUES (69, 'upsell_flow_step_experiments', :'j'::jsonb);  -- 2 rows
\set j `cat data/upsell_flow_step_variants.json`
INSERT INTO _catalog_stage VALUES (70, 'upsell_flow_step_variants', :'j'::jsonb);  -- 4 rows
\set j `cat data/upsell_flow_variant_items.json`
INSERT INTO _catalog_stage VALUES (71, 'upsell_flow_variant_items', :'j'::jsonb);  -- 173 rows
\set j `cat data/volume_discount_tiers.json`
INSERT INTO _catalog_stage VALUES (72, 'volume_discount_tiers', :'j'::jsonb);  -- 3 rows
\set j `cat data/why_you_love_it_facts.json`
INSERT INTO _catalog_stage VALUES (73, 'why_you_love_it_facts', :'j'::jsonb);  -- 392 rows
\set j `cat data/why_you_love_it_offer_facts.json`
INSERT INTO _catalog_stage VALUES (74, 'why_you_love_it_offer_facts', :'j'::jsonb);  -- 73 rows
\unset j
SELECT set_config('tfh.catalog_mode', :'mode', true);

CREATE FUNCTION pg_temp.tfh_cols(t text) RETURNS TABLE(col text, typ text) LANGUAGE sql AS $f$
  SELECT c.column_name::text, c.data_type::text FROM information_schema.columns c
  WHERE c.table_schema = 'public' AND c.table_name = t AND c.is_generated = 'NEVER'
    AND c.column_name <> 'search_vector' ORDER BY c.ordinal_position $f$;

DO $$
DECLARE r record; cols text; exprs text; upd text; has_id bool; n int; mode text := current_setting('tfh.catalog_mode');
BEGIN
  IF mode NOT IN ('replace','upsert') THEN RAISE EXCEPTION 'mode must be replace|upsert'; END IF;
  -- every staged table must exist locally (schema drift check)
  FOR r IN SELECT tbl FROM _catalog_stage WHERE to_regclass('public.'||quote_ident(tbl)) IS NULL LOOP
    RAISE EXCEPTION 'local table public.% missing (migrations behind prod?)', r.tbl;
  END LOOP;
  IF mode = 'replace' THEN
    FOR r IN SELECT tbl FROM _catalog_stage ORDER BY ord DESC LOOP
      EXECUTE format('DELETE FROM public.%I', r.tbl);
    END LOOP;
  END IF;
  FOR r IN SELECT tbl, rows FROM _catalog_stage ORDER BY ord LOOP
    -- only columns present both locally and in the export (keys of any row)
    SELECT string_agg(format('%I', c.col), ', '),
           string_agg(CASE WHEN c.typ IN ('json','jsonb')
                        THEN format('CASE WHEN jsonb_typeof(e->%L) = ''string'' THEN (e->>%L)::%s ELSE (e->%L)::%s END', c.col, c.col, c.typ, c.col, c.typ)
                        ELSE format('(jsonb_populate_record(NULL::public.%I, e)).%I', r.tbl, c.col) END, ', '),
           string_agg(format('%I = EXCLUDED.%I', c.col, c.col), ', ') FILTER (WHERE c.col <> 'id')
      INTO cols, exprs, upd
      FROM pg_temp.tfh_cols(r.tbl) c
     WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(r.rows) x WHERE x ? c.col);
    has_id := EXISTS (SELECT 1 FROM pg_temp.tfh_cols(r.tbl) WHERE col = 'id');
    EXECUTE format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_array_elements($1) e %s',
                   r.tbl, cols, exprs,
                   CASE WHEN mode = 'upsert' AND has_id THEN 'ON CONFLICT (id) DO UPDATE SET ' || upd
                        WHEN mode = 'upsert' THEN 'ON CONFLICT DO NOTHING' ELSE '' END)
      USING r.rows;
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'catalog loader: % -> % rows (exported %)', r.tbl, n, jsonb_array_length(r.rows);
    IF has_id AND pg_get_serial_sequence('public.'||quote_ident(r.tbl), 'id') IS NOT NULL THEN
      EXECUTE format('SELECT setval(pg_get_serial_sequence(%L, ''id''), GREATEST((SELECT COALESCE(max(id),0) FROM public.%I), 1))',
                     'public.'||quote_ident(r.tbl), r.tbl);
    END IF;
  END LOOP;
END $$;

-- Post-load sanity (read-only): row counts per loaded table.
SELECT s.tbl, jsonb_array_length(s.rows) AS exported,
       (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from public.%I', s.tbl), false, true, '')))[1]::text::int AS loaded
  FROM _catalog_stage s ORDER BY s.ord;
COMMIT;
-- After commit (see REPORT.md "MinIO"): POST /api/v1/sitemaps/generate on local tf-api (admin perm sitemap:edit) to
-- write the sitemap to the local MinIO SITEMAP_S3_BUCKET; catalog JSON is built by SyncCatalog (cron = forbidden; it also
-- runs after an admin product create) -> see REPORT.md for the non-cron option.
