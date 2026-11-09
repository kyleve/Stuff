# Markdown backlog migration

This directory records the one-time import into Linear’s Stuff team (`STU`).
The source revision and exact entry mapping live in `manifest.json`.
Git history retains the original Markdown files.
[BACKLOG.md](../../BACKLOG.md) owns ongoing work after cutover.

The completed import and its checks are recorded in [VALIDATION.md](VALIDATION.md).

## Records

- `manifest.json` records source hashes, entry boundaries, original text and classification, intended fields, stable IDs, views, and resulting issue links.
- `nested-tasks.json` identifies independently actionable child bullets that lack the newer typed format.
- `completion-dates.json` records manually reviewed historical completion dates and exact supporting text.

Parents retain their complete source text, including nested evidence and corrections.
Typed child tasks become sub-issues and retain the dependency defined by the original backlog contract.
Reviewed generic children are sub-issues without an inferred blocking relation.
The manifest is an immutable migration receipt after verification. It is not an editable backlog or a recurring export.

Historical dates use explicit source evidence. Origin, audit, archive, and branch dates do not become completion dates.
Date-only values use midnight UTC, with that normalization disclosed in each issue.
Linear requires creation before completion. For known completion dates without a creation date, the user approved a disclosed estimate.
The importer uses the earliest recorded origin date before completion, or one day before completion when no earlier origin exists.
Each affected issue labels its native creation date as estimated and states the basis. Other unknown dates use native import timestamps.

## Command

The root wrapper runs the importable Python modules in `Tools/`.
The transport uses the repository-pinned Linear CLI and the explicit `kve` workspace and Stuff team UUID.
It ignores dotenv files and uses the CLI’s credential mechanisms.

```sh
mise exec -- ./backlog-migrate inventory --source-ref HEAD --manifest /tmp/backlog-inventory.json --dry-run
mise exec -- ./backlog-migrate apply --dry-run
mise exec -- ./backlog-migrate apply --limit 30
mise exec -- ./backlog-migrate verify --limit 30
mise exec -- ./backlog-migrate apply
mise exec -- ./backlog-migrate verify
```

`inventory` requires the pre-migration source revision. It refuses to overwrite an existing manifest.
For the recorded import, pass the two reviewed JSON input files through `--split-nested` and `--date-evidence`.
`apply` requires unchanged original files and refuses missing, changed, or newly added backlog files.
`verify` can read deleted source files from the recorded Git revision after cutover.
`--dry-run` performs local validation without network requests or file writes.

Stable IDs make a partial import resumable. Linear requires UUIDv4-shaped client IDs; the importer derives their bytes deterministically.
After a timeout, authentication failure, or rate limit, restore access and rerun the same command and manifest.
The next run reads existing IDs before creating missing entities.
Do not regenerate the manifest or assign replacement IDs to recover from an uncertain write.

Remote content differences stop the import. The tool never overwrites issue descriptions, labels, states, or dates after creation.
Preserve human edits and reconcile the difference explicitly before continuing.
Team configuration is an apply operation: it enables Triage, disables automatic closure, and sets automatic archiving to 12 months.
Linear rejects disabling automatic archiving; the user approved this supported setting.
All history reads include archived issues.

## Cutover and post-merge handoff

The weekly triage and review-lessons jobs are paused during migration.
Their schedules, models, reasoning settings, and local execution environment remain unchanged.
Their updated prompts use Linear and report incomplete access as a blocker.

Before removing source files, verify every manifest issue and relationship against Linear.
Refresh `origin/main` and reconcile any backlog changes since inventory.
Keep the audit report’s original header date; link migration changes without claiming a new audit.
Publish the repository changes as a ready-for-review PR. Do not merge it automatically.

After the PR merges:

1. Verify that `origin/main` contains the Linear workflow instructions and removes the old backlog files.
2. Verify pinned CLI access from the automation project’s current checkout or a fresh worktree.
3. Read the two automation configurations through the automation tool.
4. Restore their previous ACTIVE status without changing schedules or other settings.
5. Record the completed cutover in the task handoff.

Do not run the old backlog workflow during the review interval.
If main receives new backlog edits before merge, reconcile them before deleting their source files.
If the migration is abandoned, preserve imported issues and reconcile them before restoring Markdown writers.
Do not mass-delete Linear work as an automatic rollback.

## Verification

The focused offline suites cover parsing, full source preservation, dates, links, dependency classification, retries, source drift, and human edits.
They also cover authentication errors, pagination, checkpoints, and dependency-free command help.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/Tests -p 'test_backlog*.py'
```

A pinned Markdown parser compares description structure after Linear normalizes escapes, links, and emphasis around code spans. Code, text, links, headings, and list structure remain significant.

Live verification checks descriptions, properties, dates, labels, parents, blocking relations, saved views, and team settings.
It verifies migration fidelity, not whether every historical claim remains true in current source.
The first subsequent weekly audit owns that re-verification.
