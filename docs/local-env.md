# Local env for tfh-automation

The suite runs on the HOST (`apps/tfh-automation`), against the stack's ports on 127.0.0.1.

## How the suite picks its env today
`config/envs.ts`: `targetEnv()` reads `TARGET_ENV` and accepts only `dev | stage | prod` (default `stage`).
Site URLs can be overridden (`FUNNEL_BASE_URL`, `MEMBER_PORTAL_BASE_URL`, `STOREFRONT_BASE_URL`, `ADMIN_BASE_URL`),
but API services (`SERVICES[env].tfApi` etc.) are hard-coded per env. So `TARGET_ENV=dev` + overrides would still
send api-* tests to the **develop** tf-api. `make verify` therefore refuses unless the suite has a `local` env.

## Suite change: tfh-automation PR #4 (`feat/local-env`, open, not merged)
https://github.com/Truly-Free-Inc/tfh-automation/pull/4 adds `local` (as sketched below, with all four sites live
except storefront) and makes the cross-env guard STRICTER for local runs (every trulyfreehome.com host = another env).
`make verify` runs `TARGET_ENV=local` and maps the seeded test customer to `MEMBER_PORTAL_USER`/`_PASSWORD`.

### Original sketch
Do not hand-edit `apps/tfh-automation` to get past verify. Open a normal PR in tfh-automation (base `main`) with:

```ts
// config/envs.ts
export type TargetEnv = 'local' | 'dev' | 'stage' | 'prod';
export const TARGET_ENVS: TargetEnv[] = ['local', 'dev', 'stage', 'prod'];

// ENVS: local site URLs = tfh-local host ports (127.0.0.1 only). null = not wired yet (tests skip).
local: {
  funnel: process.env.FUNNEL_BASE_URL || null,                       // aff-landing-pages: stub (13003)
  'member-portal': process.env.MEMBER_PORTAL_BASE_URL || null,       // memberportal: live (13001)
  storefront: null,                                                  // builderio_storefront is OUT
  admin: process.env.ADMIN_BASE_URL || null,                         // admin panel: stub (13002)
},

// SERVICES
local: {
  storefront: null,
  memberPortal: process.env.MEMBER_PORTAL_BASE_URL || null,
  admin: process.env.ADMIN_BASE_URL || null,
  my4: null,
  tfApi: process.env.TF_API_BASE_URL || 'http://127.0.0.1:13000',   // tfh-local TF_API_HOST_PORT
  apiGateway: process.env.API_GATEWAY_BASE_URL || null,             // tf-apigateway: live (13004)
  legacyFunnels: null,
  legacyLaravel: null,
},

// targetEnv(): accept 'local'
if (v === 'local' || v === 'dev' || v === 'stage' || v === 'prod') return v;

// DEFAULT_PRODUCT_SLUG: local: null
```
Also: `playwright.config.ts` builds projects from `TARGET_ENVS` filtered by `ENV`, so `api-local` etc. appear
automatically. The test-order guard (`lib/test-order-guard.ts`) is NOT changed; its cross-env host check must
treat 127.0.0.1 / localhost as the local env only (review in that PR without widening any allow-list).

## Tag syntax used in the suite
```ts
test('subscription pause shows next date', { tag: ['@TFHFUNNEL-1234', '@area-portal'] }, async ({ page }) => { ... });
test.describe('cart drawer', { tag: ['@TFHFUNNEL-1234'] }, () => { ... });
```
Gate tag: `@gate` (`npm run test:gate` = `--grep @gate --grep-invert @quarantine --retries 0`). Orders: `@order`.

## Host ports (defaults; override in .env)
| Service | Host port |
|---|---|
| tf-api | 13000 |
| Postgres | 15432 |
| Redis | 16379 |
| Mailpit UI / SMTP | 18025 / 11025 |
| MinIO API / console | 19000 / 19001 |
| Klaviyo recorder (`GET /__calls`) | 18090 |
| memberportal / admin / funnels / apigateway / vector (all live; vector needs `VECTOR=1`) | 13001 / 13002 / 13003 / 13004 / 18077 |
| Kratos public / admin (live, loopback) | 14433 / 14434 |

## Known gaps (TODO)
- Klaviyo: tf-api reads `KLAVIYO_API_BASE_URL` only on branch `tfh-local/klaviyo-base-url` (PR to develop, not merged).
  compose sets it to the recorder (`GET http://localhost:18090/__calls`) with placeholder key/list values. On a tf-api
  without that change, Klaviyo calls go to the proxy and are denied.
- S3: tf-api uses AWS SDK v2 (`AWS_ENDPOINT_URL=http://minio:9000`, virtual-host style). MinIO runs with
  `MINIO_DOMAIN=minio` and one network alias `<bucket>.minio` per bucket name from `.env`, so no tf-api change is
  needed. minio-init seeds only what exists in repo files: the vector-search repo's `search_model.json` into
  `SEARCH_MODEL_S3_BUCKET`. `make seed-sitemap` writes sitemap.xml from the local sitemap_entries (tf-api's own generator, local MinIO) and the funnels app serves it at `/sitemap.xml` (SITEMAP_S3_URL -> local MinIO). No catalog JSON (tf-api builds it only from a cron or an admin product create) or Yotpo export exists locally.
- Mail: Kratos courier -> Mailpit (`:18025`). tf-api sends via the Mailgun HTTP API, and its client deliberately
  ignores `MAILGUN_BASE_URL` (fixed base URL), so `MAILGUN_*` stays unset: tf-api mail (cancel/support/order
  emails) is not sent locally.
- Builder.io: READ-ONLY (Michael, 2026-11-19 2:57 PM ET). `proxy/readonly-allowlist.txt` holds only `cdn.builder.io`;
  preflight refuses any other entry in every mode (`READONLY_APPROVED`). Public keys come from `.env`
  (`LOCAL_BUILDER_PUBLIC_KEY_PORTAL`/`_FUNNEL`). Node's fetch ignores `HTTPS_PROXY`, so `docker/node-egress-preload.cjs`
  (NODE_OPTIONS --require) routes it through the proxy and refuses non-GET to read-only hosts. Browser-side Builder
  requests go straight from your browser (host network).
- tfhcore: an audit found remaining tfhcore calls that **will fail locally until moved to tf-api**:
  memberportal (per-page session create, addresses, search, logger, email change, old cancel flow, token refresh)
  and tf-api (cart-session fallback, Redis session dependency, two MySQL jobs). tfhcore is never configured here.

## Member portal locally (M2)
- Log in at `http://localhost:13001/login` with `TEST_CUSTOMER_PORTAL_EMAIL` / `TEST_CUSTOMER_PORTAL_PASSWORD` from `.env`
  (suite: map these to the portal test-customer variables for the `local` env).
- Login path: portal `/portal/api/v1/auth/login` -> tf-api (bcrypt in `customer_auth`) -> session in the LOCAL Redis
  (`SESSION_WRITE_NEXTGEN_REDIS_ENABLED=true`; `REDIS_HOST_TFH_CORE` is never set).
- Login-time Sticky calls fail in milliseconds (offline). `login_order_sync_enabled` has no flag row locally, so sync is skipped.
- `next dev` hydrates late: fill the login form after `load` (see `scripts/prove-portal-login.cjs`). First hit of each
  route compiles it (~20-30 s).
- Offline failures (expected): the dashboard sidebar
  (Builder symbol), Google login, Google Fonts (fallback font), GTM/Yotpo/referral scripts, portal CloudWatch
  logger (defaults to a remote develop host; DNS fails, nothing leaves), OTEL trace proxy (500, harmless), and every
  tfhcore-backed flow (addresses, header search, logger, email change, old cancel flow, token refresh).

## App mode, tf-api Basic auth (M6, Nov 19 2026)
- `LOCAL_APP_MODE=prod` (default): memberportal, admin panel and funnels run a production build (`docker/next-app-start.sh`:
  `next build` once per container, serialized across apps by a lock volume, then `next start` / the standalone server).
  Why: `next dev` keeps every compiled route's webpack graph in memory (memberportal reached 4.1-4.8 GB and restarted
  itself with "approaching the used memory threshold"), and each first hit compiled for 8-23 s. A production server
  holds only built routes. `LOCAL_APP_MODE=dev` brings back `next dev` (hot reload). `make up` / `make verify` wait for
  the builds (`scripts/warmup.sh --wait-only`). Fonts: `next/font/google` is answered offline by
  `docker/next-font-offline.cjs` (system-font fallback; Google Fonts stays blocked).
- Production builds set `Secure` cookies (`NODE_ENV=production`). Verified in the M6 gate: portal login passes on
  Chromium and WebKit (iPhone projects) over `http://localhost`.
- Funnels/portal cookie names use the deployed scheme with a `local` suffix (`tf_cart_id_local`, ...). Without
  `NEXT_PUBLIC_CART_ID_COOKIE_NAME` add-to-cart silently does nothing.
- tf-api runs with `BASIC_AUTH_ENABLED=true` like deployed envs: every route except `/ping`, `/health` and Zaymo needs
  Basic auth. `make bootstrap` generates `TF_API_BASIC_AUTH_USERNAME/PASSWORD` into `.env` (local-only values); compose
  passes them to tf-api and, as `BASIC_AUTH_USERNAME/PASSWORD` (server env only), to the three Next.js apps; `make verify`
  exports `TF_API_BASIC_AUTH=user:password` for tfh-automation. Values are never printed.

## Gate status in tfh-local (M6, Nov 19 2026) and what is skipped on purpose
`make verify` exports `BUILDER_PUBLIC_API_KEY` (the public read-only key from `.env`) and `TF_API_BASIC_AUTH` to the
suite. tfh-automation skips, only when `TARGET_ENV=local`, the tests whose answer comes from a service tfh-local keeps
offline (`lib/local-offline.ts`, reason "requires external X (offline in tfh-local)"):
- api/tax: Avalara (tax). api/address-validation: Avalara/Google/USPS.
- storefront/image-cdn: product images go through funnels' `/_next/image`, which fetches the prod image CDN server-side
  (container egress blocked by design).
- funnel/checkout-totals (TF-processor check) and cross-browser/ios-forms (card/CVV fields): TF / Spreedly payment iframes.
- platform/cf-geo: Cloudflare.
In local runs the suite also blocks the live Klaviyo, Amazon ads, Northbeam and the prod track pixel in the browser:
they hung the page `load` event and must not receive events from a local run.
Other skips are by design of the suite (admin = stage only, orders need the test-customer secrets + Sticky).

Known local failures (not offline externals):
- storefront/page-health `/` and storefront/dropoff-upsell: the funnels feature-flag proxy answers 500 for every flag
  missing locally (`e.error?.includes is not a function` on tf-api's structured 404). The local flag seed is a
  placeholder until Richard/Michael provide the approved snapshot (seed/sql/10_feature_flags.sql). Plus `/_next/image`
  500s for prod-CDN images (above).
- storefront/cart-checkout-totals: checkout is self-consistent (subtotal $19.95, savings $2.00 = the 10% volume tier,
  total $17.95), but the cart drawer's Subtotal shows the pre-discount $19.95 and the test expects it to equal the
  payable $17.95. Not confirmed whether stage's drawer shows the discounted figure (no remote calls from here).
