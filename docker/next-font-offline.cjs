// tfh-local: offline answers for `next/font/google` during `next build` (LOCAL_APP_MODE=prod).
// next build fetches font CSS from fonts.googleapis.com; the egress proxy blocks it (and must). Next's own test hook
// NEXT_FONT_GOOGLE_MOCKED_RESPONSES (set by docker/next-app-start.sh) loads this module instead: every requested
// family gets an @font-face that points at a LOCAL system font, so nothing is fetched. Same visual result as
// `next dev`, which falls back to a system font when the fetch fails.
module.exports = new Proxy({}, {
  get(_t, url) {
    if (typeof url !== 'string') return undefined;
    const m = /[?&]family=([^:&]+)/.exec(url);
    const family = decodeURIComponent((m ? m[1] : 'Fallback').replace(/\+/g, ' ')).replace(/'/g, '');
    return `@font-face {\n  font-family: '${family}';\n  font-style: normal;\n  font-weight: 400;\n  font-display: swap;\n  src: local('Arial');\n}\n`;
  },
});
