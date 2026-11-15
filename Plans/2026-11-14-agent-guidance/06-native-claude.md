# Shared instructions and linked Claude skills

Status: executing
Dependencies: [05](05-deduplication.md)
Requirements: R-01 through R-06 and X-01 through X-04 in the [overview](README.md).
Authorization: Q-08 and Q-09. Reviewed against `aaae5b0f8` on 2026-11-14.

## Design and acceptance

Claude Code now reads `AGENTS.md` natively. Project skills still require `.claude/skills/<name>/`, which supports symlinked folders.
Keep instructions in `AGENTS.md` and skill contents in `.agents/skills/`.
Create relative links for Claude skills. Stop generating instruction copies.
Remove only instruction files with the existing generated marker. Preserve other instructions and report their discovery implications.
Replace only matching skill copies or recognized links. Stop before changes on unknown or conflicting Claude skill content.
Validate migration inputs before external installation, so updates cannot erase evidence that a copy matched its original source.
Stage the new directory of links and remove marked instructions through the existing `FileTransaction`.
Commit approved copy migrations before external installation. Preserve those links if a later fetch fails, so partial updates remain retryable.
Keep pinned installation behavior and the read-only, offline checker. Missing local links remain valid on clean checkouts.
Reject legacy copies and incorrect links during checks. Do not follow linked parents outside the checkout.

The Tools contract owns mutation safety and command behavior. Existing transaction, installer, checker, and command tests provide the guards.
Add migration fixtures for fresh setup, idempotence, conflicts, linked paths, updates, and rollback.
Update active guidance and the monthly skill. Keep completed plans as historical evidence.
As a separate commit, move the Linux bootstrap to `Tools/setup-linux.sh` and update its Codex caller and documentation.
Remove the unused Cursor launcher. Preserve the bootstrap's executable body and validate the move with ShellCheck and source comparison.
Run the affected Ruby suites, command contracts, real migration, checker, and whitespace checks.
Review the complete change and obtain a fresh independent review before publishing in PR #499.
No Swift architecture sketch or additional diagram applies to this synchronous filesystem change.

## Evidence and recovery

Sources: [Anthropic instruction discovery](https://code.claude.com/docs/en/memory) and [symlinked skill folders](https://code.claude.com/docs/en/skills#choose-where-skills-load).
Native instruction loading requires Claude Code 2.1.277+ with its built-in AGENTS plugin enabled. Current releases avoid earlier provider exceptions.
Local Claude instructions can suppress native discovery under the default selection mode. Preserve these files and explain the condition.
Offline checks establish paths and content, not live model loading.

Migration implementation and focused checks pass: 54 Ruby tests with 396 assertions, 2 CLI contract tests with 130 assertions, and 33 CI tests.
The Ruby selection covers agent_files, agent_markdown, agent_guidance, agent_compatibility, agent_skill, agent_skill_installer, sync_agents, sync_agents_command, and file_transaction.
The real checkout migration removed 57 generated instructions and created 18 skill links. A second sync made no changes.
The checker passes for 57 instruction files and 13 owned skills, with a largest chain of 27,697 bytes.
Independent review found three defects: interrupted updates blocked retries, nested `.claude/CLAUDE.md` files escaped warnings, and invalid action inputs triggered migration.
Each is corrected with a regression. The author's check also found inconsistent handling of canonical asset symlinks. Sync and check now share source validation.
The complete follow-up received independent re-review against `aaae5b0f8`. No actionable findings remain.
The Linux bootstrap move preserves its executable body and mode. Its new path and Codex caller pass static inspection and pinned ShellCheck.
Publication remains pending. Live Claude loading, network installation, and Linux bootstrap execution are outside the verification scope.
On a migration conflict, keep the originals and report the exact path for reconciliation.
On apply failure, restore the prior directory and marked instructions. Preserve recovery material if rollback fails.
Resume with publication.
