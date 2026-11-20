#!/usr/bin/env node
// Headless proof: staff login to the LOCAL admin panel as the seeded local admin (Kratos + Keto role admin).
// Default flow: admin /login -> funnels /internal_admin/login (Kratos browser flow) -> back to admin.
// The funnels login form shows the password fields when feature flag enable_admin_password_login is on, and
// only accepts company-domain emails (email-domain-restriction flag; both from the seeded flag snapshot, which
// tfh-local never toggles). So LOCAL_ADMIN_EMAIL is local-admin@trulyfreehome.com (a local identity, no mailbox).
// MODE=api instead runs Kratos's browser login flow over HTTP (local Kratos only), sets it as the admin
// `sessionToken` cookie and loads the admin dashboard: proves panel + gateway + Kratos + Keto without the form.
// Every request that is not to localhost/127.0.0.1 is aborted, so the browser cannot reach any real host.
// Usage (from tfh-local root):  make prove-admin   (needs PW_MODULE like make prove-login)
const path = require('path');
const pwPath = process.env.PW_MODULE || path.join(__dirname, '..', 'apps', 'tfh-automation', 'node_modules', 'playwright');
const { chromium } = require(pwPath);

const admin = `http://localhost:${process.env.ADMIN_PANEL_HOST_PORT || 13002}`;
const funnels = `http://localhost:${process.env.FUNNELS_HOST_PORT || 13003}`;
const email = process.env.LOCAL_ADMIN_EMAIL;
const password = process.env.LOCAL_ADMIN_PASSWORD;
const shot = process.env.SHOT || path.join(__dirname, '..', '.state', 'm3-admin-login.png');
if (!email || !password) { console.error('LOCAL_ADMIN_EMAIL/_PASSWORD not set (source .env)'); process.exit(2); }

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
    if (process.env.MODE === 'api') {
      // Kratos *browser* flow over HTTP in the browser context's cookie jar (same cookies a real browser gets).
      const kratos = `http://localhost:${process.env.KRATOS_PUBLIC_HOST_PORT || 14433}`;
      const flowRes = await context.request.get(`${kratos}/self-service/login/browser`, { headers: { Accept: 'application/json' } });
      const flow = await flowRes.json();
      const csrf = (flow.ui.nodes.find((n) => n.attributes && n.attributes.name === 'csrf_token') || {}).attributes.value;
      const res = await context.request.post(flow.ui.action, {
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        data: { method: 'password', identifier: email, password, csrf_token: csrf },
      });
      const names = (await context.cookies()).map((c) => c.name);
      if (!res.ok() || !names.includes('ory_kratos_session')) throw new Error(`Kratos browser-flow login failed (HTTP ${res.status()})`);
      console.log('Kratos browser-flow login: OK (ory_kratos_session cookie set; value not printed)');
      // Same as the funnels login form (components/auth/login-form.tsx): sessionToken = session_token || session.id.
      const data = await res.json();
      await context.addCookies([{ name: 'sessionToken', value: data.session_token || data.session.id, domain: 'localhost', path: '/' }]);
      await page.goto(`${admin}/dashboard`, { waitUntil: 'load', timeout: 180000 });
      await page.waitForTimeout(15000); // client-side AuthGuard: profile + role check
      const p = new URL(page.url()).pathname;
      console.log(`ADMIN (kratos session): landed on ${admin}${p}`);
      ok = !/\/(login|forbidden)/.test(p);
      return;
    }
    await page.goto(`${funnels}/internal_admin/login?return_to=${encodeURIComponent(admin + '/dashboard')}`,
      { waitUntil: 'load', timeout: 180000 });
    const emailIn = page.locator('input[name="identifier"], input[type="email"]').first();
    const pwIn = page.locator('input[type="password"]').first();
    await emailIn.waitFor({ timeout: 60000 });
    for (let i = 0; i < 10; i++) {
      await emailIn.fill(email);
      await pwIn.fill(password);
      await page.waitForTimeout(500);
      if ((await emailIn.inputValue()) === email && (await pwIn.inputValue()) === password) break;
    }
    await page.getByRole('button', { name: /got it/i }).click({ timeout: 1500 }).catch(() => {}); // cookie banner
    // The Kratos form's submit is a type="button" labelled "Sign in with password" (not a type=submit button).
    await page.getByRole('button', { name: /sign in with password/i }).click();
    await page.waitForURL((u) => u.port === new URL(admin).port && !/\/login/.test(u.pathname), { timeout: 120000 });
    await page.waitForLoadState('load', { timeout: 120000 });
    await page.waitForTimeout(8000); // client-side AuthGuard: profile + role check
    const p = new URL(page.url()).pathname;
    const cookies = (await context.cookies()).map((c) => c.name).filter((n) => /session/i.test(n));
    console.log(`ADMIN LOGIN: landed on ${admin}${p}; session cookies: ${cookies.join(', ')}`);
    ok = !/\/(login|forbidden)/.test(p);
  } catch (e) {
    console.error(`ADMIN LOGIN FAILED: ${e.message.split('\n')[0]} (url ${page.url()})`);
  } finally {
    await page.screenshot({ path: shot, fullPage: true });
    console.log(`screenshot: ${shot}`);
    console.log(`blocked non-local hosts: ${[...blocked].sort().join(', ') || 'none'}`);
    await browser.close();
  }
  process.exit(ok ? 0 : 1);
})();
