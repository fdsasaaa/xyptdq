# Production scheduled canary marker note — 2026-08-11

The first `production_scheduled_canary` task invoked `scripts/content/run_scheduled_publish.sh` and received a zero exit status, but the task then expected the literal text `result=PASS` on its captured stdout. The scheduled runner writes its run block to its own publisher log file, so that stdout assertion is not a valid success criterion.

The task therefore reported `scheduled_runner_pass_marker_missing`. This result alone does **not** prove that the scheduled publish failed. A separate read-only verification job, `production-scheduled-canary-verify-20260811-01`, is the authoritative follow-up: it validates the durable registry, exact fixture title/content identity, Xunrui shared routing index, public HTTP status, sitemap inclusion and active publisher cron without attempting another publish.

Do not treat the original stdout-marker failure as a Publisher regression unless the independent verifier also fails.
