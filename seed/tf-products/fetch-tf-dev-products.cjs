// READ-ONLY: list every product on the TF DEV Composition API (GET /fast/api/v1/tfh-next-gen/products/, the same list
// tf-api's product sync reads). Runs INSIDE a tfh-local Node container so the request leaves only through the egress
// proxy (docker/node-egress-preload.cjs makes fetch use it). Token and base URL come from the environment
// (docker compose exec -e NAME, never argv). Prints {"total","products":[{id,uuid,sku,name,status}]} on stdout;
// never prints the token. GET only.
'use strict';
const base = String(process.env.TF_COMPOSITION_API_BASE_URL || '').replace(/\/+$/, '');
const token = process.env.TF_COMPOSITION_API_TOKEN || '';
if (new URL(base).hostname !== 'api.dev.trulyfree.com') { console.error('refusing: TF base URL is not the TF dev host'); process.exit(2); }
if (!token) { console.error('refusing: TF_COMPOSITION_API_TOKEN is empty'); process.exit(2); }
const LIMIT = 100, MAX_PAGES = 200;
(async () => {
  const products = []; let offset = 0, total = Infinity, pages = 0;
  while (offset < total && pages++ < MAX_PAGES) {
    const r = await fetch(`${base}/fast/api/v1/tfh-next-gen/products/?status=ALL&limit=${LIMIT}&offset=${offset}`,
      { method: 'GET', headers: { Authorization: token, Accept: 'application/json' } });
    if (r.status !== 200) throw new Error(`TF dev product list answered HTTP ${r.status}`);
    const j = await r.json();
    total = Number(j.total) || 0;
    const rows = Array.isArray(j.products) ? j.products : [];
    if (!rows.length) break;
    for (const p of rows) products.push({ id: p.id, uuid: p.tfhNextGenProductUuid, sku: p.sellerSku, name: p.name, status: p.status });
    offset += rows.length;
  }
  if (products.length < total) throw new Error(`incomplete TF dev product list (${products.length}/${total})`);
  process.stdout.write(JSON.stringify({ total, products }));
})().catch((e) => { console.error(`fetch-tf-dev-products: ${e.message}`); process.exit(1); });
