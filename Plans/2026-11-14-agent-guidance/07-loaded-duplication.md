# Remove guidance repeated in loaded context

Status: executing. Depends on [06](06-native-claude.md). Baseline: `6a52313e8`.
Authorization: Q-10 in the [overview](README.md). Scope: maintained guidance, with no tooling or application changes.

Remove repeated rules across ancestor instructions, required references, and skills used together.
Remove stale narrative and source inventories after checking their current owner. Retain repository-specific decisions, exceptions, and required-read routes.
Use existing owners instead of creating replacement reference files. Keep external skills and completed execution records unchanged.
The root, guidance ownership, and applicable module contracts govern the pass. The checker guards links, skill metadata, and byte budgets.

Audit common Swift/UI, test, review, publication, and planning workflows. Record retained owners for the substantive removals here.
Compare each removed obligation with its retained source, then run sync, the offline checker, and whitespace checks.
Review the complete reduction before committing and updating PR #499. No new guard or live model evaluation is required.
This is instruction consolidation; an architecture diagram or Swift sketch does not apply.

Baseline: 106 tracked guidance documents, 6,380 lines, 451,943 bytes. Root: 6,679 bytes; largest chain: 27,697 bytes.
Inventory includes AGENTS.md, owned .agents Markdown, and module Guidance documents; it excludes plans and external installations.

| Removed repetition or detail | Retained owner |
| --- | --- |
| Tool-version and command inventories, repeated icon/attribution/build instructions | Root contract, `.mise.toml`, manifests, command help, and Tools contract; unique build rules remain in build-system.md |
| Python target and Safari exception prose | `ruff.toml` and `stylelint.config.mjs`, including the compatibility comment and explicit exceptions |
| Expanded Swift examples, repeated state/composition/error advice | Concise Swift conventions; Where feature rules and scoped launch/logging contracts retain local exceptions |
| Where module type catalogs and repeated layering/store rules | Module READMEs/source, feature contract, and Swift conventions; Core's import prohibition remains local |
| Planning lifecycle, question statuses, checkpoint fields, and readiness repeated in procedures | Required `Plans/AGENTS.md`; procedures retain operation-specific steps and authorization boundaries |
| Snapshot coverage, motion, frames, and readiness repeated in preview guidance | Required SnapshotKit contract; SnapshotKitTesting owns capture mechanics and retains guard links |
| Old snapshot timing/noise measurements and repeated explanations | Current decision rules remain in framework contracts; historical evidence remains in Git and linked records |
| PR description advice repeated across tier, section, API, and review instructions | Shortened PR-writing reference retains compatibility, rollout, visual evidence, and validation requirements |

The removed global example claimed onboarding opened no store. The scoped launch contract and `WhereBootstrap.discoverRecordingDevices()` already permit preparing that store for authority discovery and reuse it for services.

Result: 106 guidance documents, 5,697 lines, 405,477 bytes: 683 fewer lines and 46,466 fewer bytes (10.3%) than `6a52313e8`.
Compared with PR base `2e27fc5ba`, maintained guidance is now 445 lines and 26,457 bytes smaller. No replacement reference files were added.
Root: 5,946/8,192 bytes. Largest instruction chain: 24,315/28,672 bytes. Largest owned entry point: code-review, 10,188/12,288 bytes.

Author comparison covered the complete changed guidance and retained owners. It restored Core's import boundary and kept adversarial tests advisory.
A fresh independent review found a missing authoring route to async capture readiness and an inaccurate claim that an old Inspector image was a current regression guard.
Both are corrected at their owners; independent re-review found no remaining actionable findings.
`mise exec ruby -- ./sync-agents`, `mise exec ruby -- ./sync-agents --check`, and `git diff --check` pass: 57 instruction files and 13 owned skills.
The bundled Python skill validator still cannot import PyYAML; repository frontmatter/link validation passes. No dependency download, app build, or live model evaluation was needed or performed.
Implementation and review are complete; next action is commit, push, and update [PR #499](https://github.com/kyleve/Stuff/pull/499).
