-- Apply the TF DEV product id mapping (map.tsv: product_id <TAB> tf_child_product_id) to the LOCAL tf_products table.
-- One transaction, idempotent: every local product ends up either SYNCED with its TF dev child id, or NOT_SYNCED with
-- no TF id (the prod TF ids from the catalog export never resolve on TF dev). Parent ids are cleared: the list API does
-- not return them and tf-api only logs them.
\set ON_ERROR_STOP 1
BEGIN;
CREATE TEMP TABLE _tf_map (product_id BIGINT PRIMARY KEY, child VARCHAR NOT NULL) ON COMMIT DROP;
\copy _tf_map FROM 'map.tsv' WITH (FORMAT text)
DELETE FROM _tf_map m WHERE NOT EXISTS (SELECT 1 FROM public.sticky_products sp WHERE sp.id = m.product_id);
INSERT INTO public.tf_products (product_id)
SELECT sp.id FROM public.sticky_products sp
WHERE NOT EXISTS (SELECT 1 FROM public.tf_products tp WHERE tp.product_id = sp.id);
UPDATE public.tf_products tp
   SET tf_child_product_id = m.child, tf_parent_product_id = NULL, tf_sync_status = 'SYNCED',
       tf_synced_at = COALESCE(CASE WHEN tp.tf_child_product_id = m.child THEN tp.tf_synced_at END, NOW()), updated_at = NOW()
  FROM _tf_map m
 WHERE tp.product_id = m.product_id
   AND (tp.tf_child_product_id IS DISTINCT FROM m.child OR tp.tf_sync_status <> 'SYNCED' OR tp.tf_parent_product_id IS NOT NULL);
UPDATE public.tf_products tp
   SET tf_child_product_id = NULL, tf_parent_product_id = NULL, tf_sync_status = 'NOT_SYNCED', tf_synced_at = NULL, updated_at = NOW()
 WHERE NOT EXISTS (SELECT 1 FROM _tf_map m WHERE m.product_id = tp.product_id)
   AND (tp.tf_child_product_id IS NOT NULL OR tp.tf_parent_product_id IS NOT NULL OR tp.tf_sync_status <> 'NOT_SYNCED');
SELECT 'tf_products: ' || string_agg(s || '=' || n, ' ' ORDER BY s) FROM
  (SELECT tf_sync_status s, count(*) n FROM public.tf_products GROUP BY 1) x;
COMMIT;
