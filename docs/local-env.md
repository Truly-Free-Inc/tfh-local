# Local env for tfh-automation

The suite runs on the HOST (`apps/tfh-automation`), against the stack's ports on 127.0.0.1.

## How the suite picks its env today
`config/envs.ts`: `targetEnv()` reads `TARGET_ENV` and accepts only `dev | stage | prod` (default `stage`).
Site URLs can be overridden (`FUNNEL_BASE_URL`, `MEMBER_PORTAL_BASE_URL`, `STOREFRONT_BASE_URL`, `ADMIN_BASE_URL`),
but API services (`SERVICES[env].tfApi` etc.) are hard-coded per env. So `TARGET_ENV=dev` + overrides would still
send api-* tests to the **develop** tf-api. `make verify` therefore refuses unless the suite has a `local` env.

## Proposed suite change (small PR in tfh-automation; NOT done by tfh-local)
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
| memberportal (live) / admin (stub) / funnels (stub) / apigateway (live) / vector (stub) | 13001 / 13002 / 13003 / 13004 / 18077 |
| Kratos public / admin (live, loopback) | 14433 / 14434 |

## Known gaps (TODO)
- tf-api Klaviyo base URL is a hard-coded constant (`constants.KlaviyoAPIBaseURL`); needs an env-override PR before
  the recorder sees tf-api calls. Until then those calls are denied by the proxy.
- S3: tf-api uses AWS SDK v2 (honours `AWS_ENDPOINT_URL`); path-style addressing for MinIO not yet confirmed.
- Mail: tf-api sends via Mailgun HTTP API, not SMTP; Mailpit currently only serves future Kratos/portal SMTP.
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
- Offline failures (expected): Builder.io pages other than `/login` and `/dashboard` (overlays), the dashboard sidebar
  (Builder symbol), Google login, Google Fonts (fallback font), GTM/Yotpo/referral scripts, portal CloudWatch
  logger (defaults to a remote develop host; DNS fails, nothing leaves), OTEL trace proxy (500, harmless), and every
  tfhcore-backed flow (addresses, header search, logger, email change, old cancel flow, token refresh).
