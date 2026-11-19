// tfh-local: make Node's global fetch (undici) use the egress proxy, and refuse writes to read-only hosts.
// Loaded with NODE_OPTIONS=--require into the Next.js dev containers (memberportal, aff-landing-pages).
// Node 20's fetch ignores HTTP(S)_PROXY, so without this server-side Builder.io fetches cannot leave at all.
// The proxy still default-denies everything except proxy/allowlist.txt + proxy/readonly-allowlist.txt.
//
// SCOPE (see docs/safety.md): the GET-only rule here covers Node's global fetch / undici ONLY. It does not see
// Node's http/https modules, axios-over-http, or browsers. The proxy allowlist is the real egress boundary.
//
// This file lives in /opt/tfh-local, so a bare require('undici') would resolve from /opt and silently miss the
// app's node_modules. Resolve from the app directory instead, and always log once whether the guard is ACTIVE.
'use strict';
const TAG = '[tfh-local egress-guard]';
function status(state, why) {
  globalThis.__TFH_EGRESS_GUARD = state;
  // Only log in the main process once (next dev forks workers that inherit NODE_OPTIONS).
  if (!process.env.__TFH_EGRESS_GUARD_LOGGED) {
    process.env.__TFH_EGRESS_GUARD_LOGGED = '1';
    console.log(`${TAG} ${state}${why ? ` (${why})` : ''}`);
  }
}

let undici;
try {
  const p = require.resolve('undici', { paths: [process.cwd(), '/app'] });
  undici = require(p);
} catch {
  // No undici in this app: global fetch has no proxy and stays offline (fails closed), but writes are not guarded here.
  status('INACTIVE', 'undici not resolvable from cwd or /app');
  return;
}
if (!undici.EnvHttpProxyAgent || !undici.setGlobalDispatcher) {
  status('INACTIVE', `undici ${undici.VERSION || '?'} lacks EnvHttpProxyAgent`);
  return;
}

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
status('ACTIVE');
