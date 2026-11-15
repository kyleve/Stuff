# GitHub workflow: merging

## Merging main and other branches

When bringing `main` or another branch into yours — because CI failed, before
a long review, or to pick up a dependency:

- **Resolve git-reported conflicts** — the `<<<<` / `>>>>` markers. Do not leave
  conflict markers or half-resolved hunks.
- **Check for logical conflicts too.** Changes on both sides can compose cleanly
  in git but still clash in behavior: a renamed symbol your branch still
  references, a relocated test helper, an updated signature your call sites don't
  match, a new invariant your code violates, duplicate registrations. Re-read
  the merged result and run `./test` (at least the affected tier) after merging
  — a clean merge is not proof the branch still makes sense.
- **Identify the revision the failing provider tested before changing branch history.**
  GitHub Actions PR jobs use the default PR merge checkout in
  [ci.yml](../../../../.github/workflows/ci.yml).
  CircleCI checks out `pipeline.git.revision` directly in
  [continue.yml](../../../../.circleci/continue.yml).
  Compare that revision, base, toolchain, and selected suites with the local run.
  If the failure is an integration conflict, bring in the current base through the applicable branch or stack workflow.
