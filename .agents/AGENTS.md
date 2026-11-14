# Agent guidance

This directory owns reusable skills and conditional repository references. Read the [repository contract](../AGENTS.md) first.
The [human guide](README.md) explains prompting. [Maintenance](references/agent-maintenance.md) owns installation and mirrors.

## Ownership and loading

- Keep universal requirements in the root contract. Put subsystem invariants in the deepest applicable `AGENTS.md`.
- Put language-specific requirements in a required reference with an explicit task trigger.
- Keep operational procedures in their existing skills. Put substantial conditional procedures and examples in skill references.
- Keep a reference's requirement and its exception together. Preserve linked guards and diagnostic signatures.
- Every extracted reference needs an explicit read condition at its owner. A link alone does not make required guidance discoverable.
- Keep one authoritative statement of a rule. Use links for consumers instead of copying the full requirement.
- Use source and manifest links for inventories and pinned versions. Keep historical evidence in linked records or conditional measurement references.
- Preserve existing skill names and invocation policies unless the requested behavior changes them.
- Give each skill a concise, discriminating description. Keep detailed operation lists in its body.
- Keep small skills self-contained. Do not add a reference layer without conditional detail to move.
- Keep relative links valid from both `.agents/skills/` and its `.claude/skills/` mirror.
  Reach shared repository references through the repository root, not through the mirror's parent directory.

## Budgets and validation

The root contract must fit 8 KiB. Each combined project instruction chain must fit 28 KiB, including separators.
Each repo-owned `SKILL.md` entry point must fit 12 KiB. Count UTF-8 bytes, not characters or estimated tokens.
These repository budgets leave headroom under Codex's default loading limit. Do not raise the local limit to hide an oversized file.

Review relocation maps for preserved requirements and exceptions. Check local links, frontmatter, and unique skill names.
Offline checks establish file structure and discovery inputs. They do not prove model activation or task quality.
Use the available skill-creator workflow when creating or substantially revising a skill.

Run `./sync-agents` after instruction or skill changes. Edit canonical sources, never generated Claude mirrors.
Follow the root attribution procedure when external skill inputs change.
