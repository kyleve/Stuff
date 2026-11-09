# Migration validation

Verified on November 9, 2026, before removing the source files.
Source revision: `c9a5cbda98c4b9f8f6aed0313d2ce2cf594cc79b`.
The final fetch of `origin/main` contained the same backlog content.

## Reconciliation

| Record | Verified result |
| --- | --- |
| Source files | 11 backlog files; the inbox contained no submissions |
| Issues | 313 unique source mappings and remote UUIDs |
| States | 147 Backlog; 166 Done |
| Nested work | 24 sub-issues; 14 blocking relations |
| Dates | 40 recorded completion dates; 40 disclosed creation-date estimates |
| Views | 18 shared views, including all 11 original areas |
| Retention | Triage enabled; automatic closure disabled; archiving after 12 months |

The first 30 issues passed verification before the remaining import continued.
The complete import then passed `backlog-migrate verify` against Linear.
Verification compared descriptions, labels, states, dates, parents, relationships, and unset assignment fields.
The manifest retains original text, classification, boundaries, hashes, stable IDs, and resulting issue links.
IDs STU-16 and STU-17 were consumed by rejected date requests; they are not missing source mappings.

Linear normalizes Markdown escapes, link serialization, and emphasis around code spans.
The verifier compares parsed content and structure, with regression cases for those transformations.
Changes to substantive text, code, links, headings, paragraphs, and nested lists still fail verification.

## Workflow rehearsal

A complete team-scoped search included every assignee, page, and archived issue.
The reviewer found [STU-10](https://linear.app/kve/issue/STU-10) as the canonical inspector-shortcut issue.
A duplicate proposal would refine that issue. An unmerged fix would stay In Review.

[STU-150](https://linear.app/kve/issue/STU-150) was reconciled against merged PR #486 and its passing parser regression.
An evidence comment records the current result and a historical date discrepancy.
Its original description, recorded completion date, and Done state remain unchanged.
This focused check does not replace the first subsequent backlog audit.

The pinned CLI authenticated through Keychain from the automation project's actual local checkout.
That shell required `mise exec` to supply Node; the access guide includes this prefix.
During import, both scheduled jobs were paused with their prior Monday schedule, model, reasoning setting, and local environment.
Post-merge completion is recorded in [README.md](README.md).

## Repository checks

- Retained Python suite: 481 tests passed before the last title/date regression additions.
- Final focused migration suite: 27 tests passed, including those additions and Markdown normalization cases.
- Public command contract: 2 tests and 135 assertions passed in the local environment.
- Lint regression probes: 8 tests passed.
- Repository Python, web, and CSS lint passed, including Python formatting.
- ShellCheck, SwiftFormat lint, attribution validation, agent sync, and diff whitespace checks passed.
- The updated triage skill passed the skill metadata validator.

Independent review identified missing date evidence, context propagation, source-drift detection, title truncation, and a completed-history link.
Those findings were corrected and checked before cutover.
The reviewer also exercised content-preservation failures against the Markdown comparator.

No application behavior changed. Swift edits only replace backlog references in comments.
Simulator, application-build, and screenshot tests were not run for this migration.

## Post-merge completion

PR #491 merged on November 9, 2026, at `0e95a9398c382ff6d28ef46c9474718023f14ccb`.
The merged guidance, source-file removal, all 313 issues, and local automation access were verified.
Both existing jobs resumed through the automation tool with their prior schedules and settings.
The first subsequent audit must re-verify the imported historical claims.
