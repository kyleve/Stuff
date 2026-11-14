# Stuff — Repository contract

Read this file first. Then read every descendant `AGENTS.md` that applies to the affected paths, including source directories.
When starting at the repository root, discover those descendants before editing; they are not all loaded automatically.
Read the required references below for the task. They carry the same authority as the owning instructions.

Library targets live in `Package.swift`. App, extension, and test targets live in `Project.swift` and `Tuist.swift`.
Shared modules live under `Shared/`; Where modules live under `Where/`.
Use each module's `README.md` for its API and its `AGENTS.md` for its contracts.
Read exact tool versions from `.mise.toml`, lockfiles, and `.xcode-version`.

## Required task guidance

Read the matching reference before implementation or review. Read only relevant sections of long references.

| Task | Required guidance |
| --- | --- |
| Any Swift source or test change | [Swift conventions](.agents/references/swift-conventions.md) |
| Build tools, project generation, icons, audiences, metadata, attribution, or architecture enforcement | [Build system](.agents/references/build-system.md) |
| Target graph, package links, snapshots, deployment, signing, or distribution | [Targets and distribution](.agents/references/targets.md) |
| Run tests, choose coverage, debug a simulator, or review snapshot differences | [running-tests](.agents/skills/running-tests/SKILL.md) |
| Create, change, or review SwiftUI/UIKit UI, styling, accessibility, previews, or snapshots | [building-ui](.agents/skills/building-ui/SKILL.md) |
| Add or change module documentation, repository rules, or plans | [Documentation contracts](.agents/references/repository-docs.md) |
| Change agent instructions, skills, or their installation | [Guidance ownership](.agents/AGENTS.md) and [agent maintenance](.agents/references/agent-maintenance.md) |
| Worktree setup, cleanup, Linux limitations, or CI behavior | [Environments and CI](.agents/references/environments.md) |
| Change a root command or its policy implementation | [Tools contract](Tools/AGENTS.md) |

## Essential commands and boundaries

- Regenerate with `./ide --no-open`. Never open Xcode or bypass the setup with `tuist generate`.
- Use `./test` for iOS bundles. Never hand-roll `tuist test` or `xcodebuild` for them.
- Use root commands for their owned state. Read `--help` instead of reimplementing a command.
- Use `./icons` for icon catalogs and manifests. Never hand-edit them or add icon Swift.
- Run `./attribution` after adding or updating a package, external skill, or development tool. Commit the report.
- Run `./test --architecture-only` after a Where dependency, composition-root, or documented concurrency-boundary change.
- Keep generated `.xcodeproj`, `Derived/`, `CLAUDE.md`, and `.claude/skills/` files out of commits.
- Bundle IDs follow `com.stuff.<suffix>`.
- Keep the invariant, executable rule, rule catalog, and mutation test together when changing architecture enforcement.
- Keep module README and agent instructions current when architecture, public API, conventions, or documented behavior changes.
- Linear's Stuff team owns actionable work. Follow [BACKLOG.md](BACKLOG.md); unavailable access does not establish an empty backlog.
- Durable plans live in [Plans/](Plans/README.md). Use the [planning skill](.agents/skills/planning/SKILL.md) for their lifecycle.

## Formatting

- **Python and web correctness:** `mise exec -- npm run lint` runs pinned Ruff, type-aware ESLint, Astro rules, and Stylelint. `npm run test:lint` proves that representative errors fail. Ruff targets Python 3.9. Keep formatting-only changes separate from behavior changes.
- **Python formatting:** `mise exec -- npm run format:python` applies Ruff formatting. The shared lint command checks formatting without changing files. CSS uses the pinned standard Stylelint preset; preserve the three documented Safari property exceptions in `stylelint.config.mjs`.
- **SwiftFormat** uses [`.swiftformat`](.swiftformat). Run `./swiftformat` to
  format the tree. Run `./swiftformat --lint` to make sure that formatting is correct (as in CI).
- **ShellCheck** is pinned in [`.mise.toml`](.mise.toml). `./shellcheck` discovers
  and lints every tracked shell file by its shebang.
- The pre-commit hook (enabled by `./ide` via `core.hooksPath`) formats staged
  `*.swift` files in place and re-stages them.
- **String Catalogs are stored exactly as Xcode serializes them**. `./xcstrings` (`--lint` in CI) enforces this. A catalog written by anything
  else parses fine. The next IDE build then produces thousands of lines of
  whitespace churn. Write catalogs through Xcode. Or normalize with the
  script afterwards (it touches formatting only, never content).

## Working in this repo

- **Identify the applicable rules before implementation.** For behavior changes,
  name the relevant invariants and their existing guards in the task's working plan.
  Use the owning `AGENTS.md` and required skills. If the scope expands, read the
  new area's instructions before editing it. Keep this map task-local.
- **Never commit on `main`.** Branch first (`git checkout -b <name>`). Keep
  every commit for one piece of work on that one branch.
- **Run checks in proportion to risk.** Follow [Running tests](.agents/skills/running-tests/references/test-contract.md#running-tests).
  Never commit a known-red tree. Load the
  [`running-tests`](.agents/skills/running-tests/SKILL.md) skill to choose
  the applicable checks.
- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit and push completed work eagerly.** Once a coherent change is
  verified, commit it and push the current feature branch. Do not wait for a
  separate request. Never hand back a finished task with task-related changes
  left local, unpushed, or uncommitted. Honor an explicit request to keep work
  local or uncommitted.

### GitHub

Load the [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill
for PRs, pushes, review feedback, CI, and posting as the user. Always-on: use
`gh`. Open PRs ready-for-review. Mark AI-posted comments. **Plan-driven work
ends with push + PR** before handing back. **Addressing review feedback
includes GitHub replies** on the threads you touch — not code-only fixes.

Use [`review-lessons`](.agents/skills/review-lessons/SKILL.md) for the monthly
PR-history audit or an explicit review of recurring failures.
Use [`code-review`](.agents/skills/code-review/SKILL.md) for PR or branch reviews
and the completed-diff review before publication. It owns review procedure and evidence.
`github-workflow` owns publication and replies.
