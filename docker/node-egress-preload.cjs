// tfh-local: make Node's global fetch (undici) use the egress proxy, and refuse writes to read-only hosts.
// Loaded with NODE_OPTIONS=--require into the Next.js dev containers (memberportal, aff-landing-pages).
// Node 20's fetch ignores HTTP(S)_PROXY, so without this server-side Builder.io fetches cannot leave at all.
// The proxy still default-denies everything except proxy/allowlist.txt + proxy/readonly-allowlist.txt.
'use strict';
let undici;
try { undici = require('undici'); } catch { return; } // no undici in this app: fetch stays offline (fails closed)
if (!undici.EnvHttpProxyAgent || !undici.setGlobalDispatcher) return;

// Read-only hosts (keep in sync with proxy/readonly-allowlist.txt): only GET/HEAD/OPTIONS may go there.
const READ_ONLY = /^cdn\.builder\.io$/i;
const READ_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

class ReadOnlyGuardAgent extends undici.EnvHttpProxyAgent {
  dispatch(opts, handler) {
    let host = '';
    try { host = new URL(String(opts.origin)).hostname; } catch {}
    const method = String(opts.method || 'GET').toUpperCase();
    if (READ_ONLY.test(host) && !READ_METHODS.has(method)) {
      throw new Error(`tfh-local: ${method} to read-only host ${host} refused (docker/node-egress-preload.cjs)`);
    }
    return super.dispatch(opts, handler);
  }
}
undici.setGlobalDispatcher(new ReadOnlyGuardAgent());
