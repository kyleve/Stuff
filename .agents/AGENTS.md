# Agent guidance

Read the [repository contract](../AGENTS.md). [Maintenance](references/agent-maintenance.md) covers installation and Claude compatibility.

## Ownership and loading

- Keep one owner per rule: universal rules in the root contract, local invariants in module instructions, and procedures in skills.
- Remove generic advice and behavior evident from code. Retain explicit preferences, non-obvious constraints, exceptions, and useful guards.
- Conditional references need explicit read conditions. Preserve exceptions and guard links when moving rules.
- Preserve skill names and invocation policies unless the requested behavior changes them.
- Skill links must work from both `.agents/skills/` and `.claude/skills/`; reach shared references through the repository root.

## Budgets and validation

Limits are 8 KiB for the root contract, 28 KiB per combined instruction chain including separators, and 12 KiB per owned `SKILL.md`, counted as UTF-8 bytes.
Do not increase loading limits to hide oversized guidance.

Run `./sync-agents`, then `./sync-agents --check`. See [checker scope](../Tools/README.md#agent-guidance-tools) for coverage and parser limits.
