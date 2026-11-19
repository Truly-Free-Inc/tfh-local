# AI ticket loop (follow verbatim, one ticket at a time)

## SAFETY (read first, every time)
- **No production anything.** Never Syteline/Infor. Never configure tfhcore or Avalara.
- **Real non-prod Sticky + TF, TEST ORDERS ONLY** ("test test" customer + test cards).
- **Never touch or widen** tfh-automation `lib/test-order-guard.ts`. **Never change feature flags.**
- **Never bypass** `scripts/preflight.sh` or edit `safety/`, `proxy/allowlist.txt` to get past a refusal.
- **No secrets** in commits, logs, PR bodies or chat. **Open PRs, NEVER merge** (no approve, no force-push).
- Anything odd (non-test order, prod host, flag change, secret in output): **STOP and report to Michael.**
Full rules: [safety.md](safety.md).

## Steps
Let `KEY` be the Jira key (e.g. `TFHFUNNEL-1234`).

1. **Start the ticket**
   ```bash
   cd ~/projects/tfh-local
   make bootstrap            # first time only
   make ticket KEY=$KEY      # add BRANCH=... if the ticket names a branch
   make status
   ```
   If `make ticket` refuses because a repo is dirty, stop and report; do not stash or discard someone's work.

2. **Build the feature on the ticket branch** in `apps/<repo>/`.
   If the repo has no ticket branch yet, create one from its default branch:
   `git -C apps/<repo> checkout -b feature/$KEY-<short-desc>`. Commit with the key in the message
   (`$KEY: <what changed>`). Only touch repos the ticket needs.

3. **Write the test in tfh-automation on the same ticket branch** (`apps/tfh-automation`, branch `$KEY`),
   tagged with the key:
   ```ts
   test('what the ticket guarantees', { tag: ['@TFHFUNNEL-1234'] }, async ({ page }) => { /* ... */ });
   ```
   Orders only through the existing guard/fixtures ("test test" + test cards). Commit: `$KEY: test ...`.

4. **Run locally**
   ```bash
   make up
   make verify KEY=$KEY
   ```
   `verify` = preflight + health + your `@$KEY` tests + the core gate (`@gate`, minus `@quarantine`) +
   test-order check. Results: `.state/runs/$KEY-<ts>/summary.md`.

5. **Fix loop (time-boxed): at most 5 verify attempts or 45 minutes, whichever comes first.**
   Read the failing log, fix code or test (never weaken a guard, never skip/quarantine the failing core test,
   never change flags), commit, `make verify KEY=$KEY` again. If still red at the limit: **STOP** and report
   the last `summary.md`, the failing tests and what you tried.

6. **Open PRs (only when verify is GREEN on the current commits)**
   ```bash
   make pr KEY=$KEY            # dry run: read the plan
   make pr KEY=$KEY CONFIRM=1  # push + open PRs to develop (main where no develop)
   ```
   GitHub repos get a PR via `gh`. Bitbucket repos: open the printed URL and paste the printed body file.
   **Never merge.**

7. **Report**: ticket key, branch per repo, PR links (or Bitbucket URLs), verify summary path and result.
   End shared-channel posts with `* posted by AI bot`.
