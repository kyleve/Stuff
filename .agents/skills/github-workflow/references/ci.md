# GitHub workflow: ci

## CI

- Start with `gh pr checks <pr>` to identify the failing provider, check, and
  job URL. Use GitHub Actions logs for GitHub-hosted checks.
- For a failed CircleCI check, use the repository-owned
  `./circleci-artifacts <job-uuid-or-url>` script instead of scraping the web
  UI. It downloads the job bundle to
  `.build/circleci-artifacts/<job-uuid>` by default and requires an
  authenticated CircleCI CLI.
- Read the smallest diagnostic artifact first. Snapshot jobs publish
  `snapshots/diagnostics/test-output/failures.json` and `diffs.jsonl`; inspect
  the corresponding actual/reference images under
  `snapshots/diagnostics/snapshot-images` before recording any reference.
- **Don't block the conversation polling CI.** Report what's running and hand
  the turn back. Delegate a genuine watch to a background subagent.
