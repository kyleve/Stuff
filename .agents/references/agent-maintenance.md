# Maintain agent guidance

## Agent instructions sync

`AGENTS.md` is the source of truth for AI agent instructions. Cursor reads
`AGENTS.md` natively. Claude Code uses `CLAUDE.md` and `.claude/skills/`.
Generated files (`CLAUDE.md`, `.claude/skills/`) are gitignored and produced
by `./sync-agents`.

- `./sync-agents` — generate `CLAUDE.md` next to each `AGENTS.md` and mirror
  `.agents/skills/` into `.claude/skills/`.
- `./sync-agents --install` — fetch external skills listed in
  `.agents/external-skills.json`. Rarely run by hand. `mise install` calls it
  from a `postinstall` hook. Installing tools also installs skills on a dev
  machine and a cloud agent. CI sets `MISE_NO_HOOKS=1` because CI does not use
  agent skills.
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills to the latest commit.

`.agents/external-skills.json` pins the **external** skills to a commit.
`.agents/skills/.gitignore` excludes those fetched copies. Anything else
under `.agents/skills/` is **repo-owned** and committed. External skills are
also an **attribution** input. After adding or updating one, re-run
`./attribution` (see [Attribution](build-system.md#attribution)). The same applies to
`.agents/development-tools.json` when pinned verification or other non-SPM
tooling changes.

**`.agents/skills/` is the real home**. Edit the source. Never edit the
`.claude/skills/` mirror. Run `./sync-agents` after adding or editing a
skill. Cursor loads both directories. The winning copy is undocumented.
Do not let them drift. A fresh clone carries only the repo-owned skills. The
external ones arrive with the first `mise install`.

A skill carries **procedure**. That is the steps of an occasional job. It includes
rules that apply only while that job runs (GitHub, running tests, backlog
triage). **Always-on** rules every edit must honor stay in `AGENTS.md`. Language-specific rules can live in required task references with explicit read conditions. Backlog rules live in [BACKLOG.md](../../BACKLOG.md).

Put a new invariant in the deepest `AGENTS.md` that covers its consumers.
Use a scoped source-directory file when only one subsystem needs it.
Before adding guidance, find its existing owner and strengthen that rule instead of adding another copy.
Keep the review history in the PR and link the rule to its guard or source.
