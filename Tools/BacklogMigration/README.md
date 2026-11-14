# Markdown backlog migration record

The one-time migration to Linear’s Stuff team (`STU`) completed on November 9, 2026.
[PR #491](https://github.com/kyleve/Stuff/pull/491) merged the backlog and workflow changes.
All 313 issues passed verification after merge. The weekly triage and review-lessons jobs then resumed with their original schedules.
[BACKLOG.md](../../BACKLOG.md) owns ongoing work.

## Retained records

- [manifest.json](manifest.json) records source revisions, hashes, entry boundaries, original text, classification, intended fields, stable IDs, and Linear issue links.
- [VALIDATION.md](VALIDATION.md) records import verification, the workflow rehearsal, repository checks, and their limits.

The manifest is an immutable historical receipt. It is not an editable backlog or a recurring export.
Git history retains the original Markdown files.

The migration command, implementation, tests, and separate input files were removed after cutover.
They remain available at [the migration commit](https://github.com/kyleve/Stuff/tree/0e95a9398c382ff6d28ef46c9474718023f14ccb).
If the importer is needed again, revert the tooling-removal commit.
The manifest also retains the reviewed nested-task selections and completion-date evidence.

## Historical dates

Date-only values use midnight UTC. Issues with recorded historical dates disclose this convention.
Linear requires creation before completion. For 40 known completion dates without creation dates, the user approved disclosed estimates.
Each affected issue states the estimate and its basis. Other unknown dates use native import timestamps.
The import preserves recorded claims. The first subsequent audit owns their re-verification.
