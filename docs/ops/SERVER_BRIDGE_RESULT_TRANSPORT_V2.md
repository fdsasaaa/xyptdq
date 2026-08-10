# Server Bridge result transport V2

The production worker does not require GitHub write credentials.

## Control path

1. ChatGPT creates reviewed job JSON on canonical `main`.
2. The server systemd timer fetches public `origin/main`.
3. The worker validates the job ID, exact required commit, approved script path, script SHA-256 and timeout.
4. The approved task runs once. Raw logs remain root-only under `/var/log/xyptdq-agent`.

## Result path

1. The worker validates the task payload and rejects credential-bearing keys, private-key material and credential-bearing URLs.
2. The sanitized result is written under the deployment-preserved `uploadfile/xyptdq-agent-results/` directory.
3. `.github/workflows/agent-collect.yml` polls only known pending job IDs, independently validates the returned result against the job commit/script/hash, and commits accepted JSON into `ops/jobs/results/`.
4. No server-side Git push credential is required.

This transport is intentionally limited to non-secret structured result data. It does not publish raw task logs, database configuration, dumps, credentials, tokens or private keys.
