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

// Next.js middleware runs in the edge-runtime sandbox (a vm context with its own bundled undici fetch). That fetch
// cannot see the global dispatcher set above, so middleware fetches (e.g. the storefront's Builder url-redirects
// rules) bypassed both the proxy and the read-only guard and simply failed offline. Hand the sandbox the guarded
// Node fetch instead: same proxy allowlist, same GET-only rule. Requests whose body or signal cannot cross the
// realm safely keep the sandbox's own fetch (which has no route out of the internal network: fails closed).
const Module = require('module');
const guardedFetch = globalThis.fetch;
function crossRealmInit(init) {
  if (!init) return {};
  const out = {};
  for (const k of ['method', 'cache', 'credentials', 'integrity', 'keepalive', 'mode', 'redirect', 'referrer', 'referrerPolicy']) {
    if (init[k] !== undefined) out[k] = init[k];
  }
  if (init.headers) out.headers = Array.from(typeof init.headers[Symbol.iterator] === 'function' ? init.headers : Object.entries(init.headers));
  const b = init.body;
  if (b !== undefined && b !== null) {
    if (typeof b === 'string') out.body = b;
    else if (ArrayBuffer.isView(b)) out.body = Buffer.from(b.buffer, b.byteOffset, b.byteLength);
    else if (Object.prototype.toString.call(b) === '[object ArrayBuffer]') out.body = Buffer.from(b);
    else if (Object.prototype.toString.call(b) === '[object URLSearchParams]') out.body = String(b);
    else return null;
  }
  const s = init.signal;
  if (s) {
    if (typeof s.addEventListener !== 'function') return null;
    const ac = new AbortController();
    if (s.aborted) ac.abort(s.reason); else s.addEventListener('abort', () => ac.abort(s.reason), { once: true });
    out.signal = ac.signal;
  }
  return out;
}
const origLoad = Module._load;
Module._load = function tfhLocalLoad(request, parent, isMain) {
  const exp = origLoad.apply(this, arguments);
  if (request !== 'next/dist/compiled/edge-runtime' || !exp || typeof exp.EdgeRuntime !== 'function' || exp.__tfhGuarded) return exp;
  const Base = exp.EdgeRuntime;
  class GuardedEdgeRuntime extends Base {
    constructor(opts = {}) {
      const userExtend = opts.extend;
      super({
        ...opts,
        extend: (ctx) => {
          const sandboxFetch = ctx.fetch;
          ctx.fetch = (input, init) => {
            // Next's sandbox wrapper always passes a URL string; anything else keeps the sandbox fetch.
            const i = typeof input === 'string' ? crossRealmInit(init) : null;
            return i === null ? sandboxFetch(input, init) : guardedFetch(input, i);
          };
          return userExtend ? userExtend(ctx) : ctx;
        },
      });
    }
  }
  const wrapped = Object.assign(Object.create(Object.getPrototypeOf(exp)), exp, { EdgeRuntime: GuardedEdgeRuntime, __tfhGuarded: true });
  return wrapped;
};
