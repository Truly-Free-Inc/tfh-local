# cron/

**Pending discussion with Michael — local and stage cron runs.**

The `cron` compose profile exists, but its service is a stub that refuses to run (exits 1). tf-api crons must not
be run locally until the design is agreed (on-demand runner, `-dry-run` / test-only filters, test-order scoping;
several stage jobs touch real Sticky/TF). Background: `.work/local-stack-plan-1119.md` section 6 in doaty-brain.
