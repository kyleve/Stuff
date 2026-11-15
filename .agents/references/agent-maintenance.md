# Maintain agent guidance

## Shared instructions and skills

`AGENTS.md` is the shared instruction source. Do not generate `CLAUDE.md` copies.
Claude Code 2.1.277+ supports native `AGENTS.md` discovery through its built-in AGENTS plugin.
Use 2.1.281+ to avoid the early provider and telemetry exceptions. Keep that plugin enabled.
See [Anthropic's instruction documentation](https://code.claude.com/docs/en/memory).

Under the default Project instructions setting, local `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md` files can suppress native discovery.
This includes matching files in ancestor directories. User-level `~/.claude/CLAUDE.md` does not suppress it.
If local Claude instructions are intentional, select `claude-md-and-agents-md` in `/config` to load both formats.
Use `/context all` to inspect the loaded memory files. The repository checker does not inspect user settings or ancestor files.
Claude does not auto-load instructions under `.agents/` or `AGENTS.override.md`. Keep required-read routes for conditional references in the owning instructions.

Claude project skills use `.claude/skills/<name>/`. Each folder is a relative symlink to `.agents/skills/<name>/`.
[Anthropic supports these skill-folder links](https://code.claude.com/docs/en/skills#choose-where-skills-load).
Skill content exists once. Keep the links untracked and edit canonical files.

- `./sync-agents` — remove marked generated instructions and replace matching skill copies with links. Maintain links for installed skills.
- `./sync-agents --check` — validate instructions, skills, local links, and compatibility paths without changing files or fetching dependencies.
- `./sync-agents --install` — fetch missing or invalid external skills at their pinned revisions, then maintain the links.
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills at their latest commits.

Migration preserves unmarked instruction files and reports their discovery implications.
Unknown Claude skill entries or differing copies stop sync before installation or cleanup. Reconcile the reported files before retrying.
The generated marker identifies removable instruction copies. Skill copies must match canonical contents and modes before replacement.
Approved copy migrations commit before external installation. If a later fetch fails, the links remain valid for retry.
The [tool contract](../../Tools/README.md#agent-guidance-tools) covers validation and rollback.

`mise install` runs `--install` through its postinstall hook. `./ide` also runs it during setup.
CI sets `MISE_NO_HOOKS=1` because CI does not use agent skills.

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

For canonical edits and link setup, read [guidance ownership](../AGENTS.md).
A fresh clone carries only repo-owned skills. External skills arrive with the first `mise install`.

### Optional writing guidance

`simple-english` is no longer installed by repository setup. Install [SimpleEnglish](https://github.com/AminBlg/SimpleEnglish/tree/59bf6702197a5aadc96d197ea17f290d8d50dcd3/skills/simple-english) as a personal skill when controlled-language writing is wanted.
Existing checkouts can still contain its ignored installation. Move `.agents/skills/simple-english/` outside skill-discovery directories to retire it locally, then run `./sync-agents` to remove its Claude link. Preserve any local edits.

## Periodic normalization

Use [normalize-agent-guidance](../skills/normalize-agent-guidance/SKILL.md) for the monthly audit or a requested instruction cleanup.
CI enforces the hard budgets. The skill reviews growth, ownership, duplication, and required-read routes, then publishes supported corrections for review.
Keep the procedure in the skill and the cadence in the scheduler. A clean run needs no commit or PR.
