# Maintain agent guidance

## Agent instructions sync

`AGENTS.md` is the source of truth for AI agent instructions. Cursor reads
`AGENTS.md` natively. Claude Code uses `CLAUDE.md` and `.claude/skills/`.
Generated files (`CLAUDE.md`, `.claude/skills/`) are gitignored and produced
by `./sync-agents`.

- `./sync-agents` — generate `CLAUDE.md` next to each `AGENTS.md` and mirror
  `.agents/skills/` into `.claude/skills/`.
- `./sync-agents --check` — validate instructions, skills, local links, and present mirrors without changing files or fetching dependencies.
- `./sync-agents --install` — fetch external skills listed in
  `.agents/external-skills.json`. It repairs invalid layouts at the pinned revision. Rarely run by hand. `mise install` calls it
  from a `postinstall` hook. Installing tools also installs skills on a dev
  machine and a cloud agent. CI sets `MISE_NO_HOOKS=1` because CI does not use
  agent skills.
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills to the latest commit.

`.agents/external-skills.json` pins the **external** skills to a commit.
Its optional `exclude` list removes relative packaging paths from the staged skill.
Keep exactly one root `SKILL.md` with the manifest name. Preserve referenced resources.
Add, install, and update validate the candidate before transactional replacement.
See the [installer contract](../../Tools/README.md#agent-guidance-tools).
`.agents/skills/.gitignore` excludes those fetched copies. Anything else
under `.agents/skills/` is **repo-owned** and committed. External skills are
also an **attribution** input. After adding or updating one, re-run
`./attribution` (see [Attribution](build-system.md#attribution)). The same applies to
`.agents/development-tools.json` when pinned verification or other non-SPM
tooling changes.

For canonical edits and mirror synchronization, read [guidance ownership](../AGENTS.md).
Cursor loads both skill directories. The winning copy is undocumented, so do not let them drift.
A fresh clone carries only repo-owned skills. External skills arrive with the first `mise install`.

## Periodic normalization

Use [normalize-agent-guidance](../skills/normalize-agent-guidance/SKILL.md) for the monthly audit or a requested instruction cleanup.
CI enforces the hard budgets. The skill reviews growth, ownership, duplication, and required-read routes, then publishes supported corrections for review.
Keep the procedure in the skill and the cadence in the scheduler. A clean run needs no commit or PR.
