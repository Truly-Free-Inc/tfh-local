#!/usr/bin/env node
// Headless proof: log in to the LOCAL member portal as the seeded test customer and land on /dashboard.
// Every request that is not to localhost/127.0.0.1 is aborted, so the browser cannot reach any real host.
// Usage (from tfh-local root):  set -a; . ./.env; set +a; node scripts/prove-portal-login.cjs
//   PW_MODULE=/path/to/node_modules/playwright  (default: apps/tfh-automation/node_modules/playwright)
//   SHOT=.state/m2-login.png                    (screenshot path)
// Selectors and the post-login URL wait mirror tfh-automation pages/MemberPortalLoginPage.ts.
const path = require('path');
const pwPath = process.env.PW_MODULE || path.join(__dirname, '..', 'apps', 'tfh-automation', 'node_modules', 'playwright');
const { chromium } = require(pwPath);

const base = `http://localhost:${process.env.MEMBERPORTAL_HOST_PORT || 13001}`;
const email = process.env.TEST_CUSTOMER_PORTAL_EMAIL;
const password = process.env.TEST_CUSTOMER_PORTAL_PASSWORD;
const shot = process.env.SHOT || path.join(__dirname, '..', '.state', 'm2-login.png');
if (!email || !password) { console.error('TEST_CUSTOMER_PORTAL_EMAIL/_PASSWORD not set (source .env)'); process.exit(2); }

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext();
  const blocked = new Set();
  await context.route('**/*', (route) => {
    const host = new URL(route.request().url()).hostname;
    if (host === 'localhost' || host === '127.0.0.1') return route.continue();
    blocked.add(host);
    return route.abort();
  });
  const page = await context.newPage();
  let ok = false;
  try {
    await page.goto(`${base}/login`, { waitUntil: 'domcontentloaded', timeout: 120000 });
    // `next dev` hydrates late; fill only after load and re-fill until React keeps the values.
    await page.waitForLoadState('load', { timeout: 120000 });
    const emailIn = page.locator('input#email[name="email"]');
    const pwIn = page.locator('input#password[name="password"]');
    for (let i = 0; i < 10; i++) {
      await emailIn.fill(email);
      await pwIn.fill(password);
      await page.waitForTimeout(500);
      if ((await emailIn.inputValue()) === email && (await pwIn.inputValue()) === password) break;
    }
    const t0 = Date.now();
    await page.locator('form:has(input#password) button[type="submit"]').click();
    await page.waitForURL(/\/(dashboard|auth\/first-login)/, { timeout: 60000 });
    const ms = Date.now() - t0;
    await page.waitForLoadState('domcontentloaded');
    await page.waitForTimeout(1500);
    const cookies = (await context.cookies()).map((c) => c.name).filter((n) => /session/i.test(n));
    console.log(`LOGIN OK: landed on ${new URL(page.url()).pathname} ${ms} ms after submit; session cookies: ${cookies.join(', ')}`);
    ok = true;
  } catch (e) {
    console.error(`LOGIN FAILED: ${e.message.split('\n')[0]} (url ${page.url()})`);
  } finally {
    await page.screenshot({ path: shot, fullPage: true });
    console.log(`screenshot: ${shot}`);
    console.log(`blocked non-local hosts: ${[...blocked].sort().join(', ') || 'none'}`);
    await browser.close();
  }
  process.exit(ok ? 0 : 1);
})();
