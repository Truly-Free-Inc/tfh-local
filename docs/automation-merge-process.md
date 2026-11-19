# tfh-automation merge process

How changes to the tfh-automation suite get merged, and how we keep the suite itself healthy.
Status: **process defined; checks and guard are to be built.** AI merge stays OFF until they exist.

## 1. Per-PR checks before merge
1. **Static checks:** type check, lint, and a test-listing dry run that catches broken imports, duplicate test titles and missing ticket tags.
2. **Repeat runs:** the PR's new or changed tests run back-to-back locally against the local stack and must pass every time. Count: **3 or 5 (open, Michael to decide).**
3. **Core gate:** passes once with the change in place.
4. **GitHub:** runs the static checks plus only the PR's tests, not the full suite (to save cost).

## 2. Scope guard (required)
A PR may **only add or change its own ticket's feature test files** (tagged with the ticket key). It may **not modify, delete, skip or retag any other test** in the suite.

Blocked unless a human adds a sign-off label:
- `lib/test-order-guard.ts`
- safety config
- shared fixtures, helpers and config
- CI workflows

Enforcement (**to be built**): a script diffs the PR against develop and fails if any changed test file is not owned by the ticket key (or if a blocked path changed without the label). It runs locally in `make verify-suite` and as a required GitHub check.

## 3. Merge rule
Decision (Michael): AI may merge once proper checks and guards are in place. Rule: AI may merge into develop only when **all required checks pass, the scope guard is green, and the branch is up to date with develop**. Anything else stays open for a human. The guard and the checks must exist and be required before AI merge is turned on. Promotion from develop to main is batched.

## 4. How suite runs work (agreed direction)
1. **Standard suite = regression + core.** Ticket and feature tests are excluded from it.
2. **When a branch merges to an environment (develop, stage),** the run is the standard suite plus **that branch's own feature tests only**.
3. **Ticket tests join regression later** through a QA promotion process, probably after release. This is an open topic to brainstorm: when, and how tags change.
   Decision (Michael): the QA engineer, Puneet, kicks off the promotion of a ticket's feature tests into regression and signs off on it. He may use AI to do the promotion work.
4. **Quarantine (proposal):** a test that fails and passes on rerun is tagged to stop blocking merges while it is fixed, with a Jira ticket and a fix deadline.

## 5. Open items
- Back-to-back count: 3 or 5.
- Fix deadline length for quarantined tests.
- Who owns the quarantine tickets.
- QA promotion of feature tests into regression (timing and mechanics; owner decided: Puneet).
