# Stuff — Repository contract

Read the descendant `AGENTS.md` files for affected paths, including source directories; they are not all loaded when starting at the root.
Task-specific references below carry the owning instructions' authority.

Use module READMEs for APIs and local instructions for contracts.
`Package.swift` owns libraries; `Project.swift` and `Tuist.swift` own app, extension, and test targets.
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
- Use `./prototype` for Astro prototype servers and checks; see [tooling details](Tools/README.md#browser-prototypes).
- Use `./icons` for icon catalogs and manifests. Never hand-edit them or add icon Swift.
- Run `./attribution` after adding or updating a package, external skill, or development tool. Commit the report.
- Run `./test --architecture-only` after a Where dependency, composition-root, or documented concurrency-boundary change.
- Keep generated `.xcodeproj`, `Derived/`, local `CLAUDE.md`, and `.claude/skills/` links out of commits.
- Bundle IDs follow `com.stuff.<suffix>`.
- Keep the invariant, executable rule, rule catalog, and mutation test together when changing architecture enforcement.
- Keep affected module documentation current; retain instructions for decisions not evident from code.
- Linear's Stuff team owns actionable work. Follow [BACKLOG.md](BACKLOG.md); unavailable access does not establish an empty backlog.
- Durable plans live in [Plans/](Plans/README.md). Use the [planning skill](.agents/skills/planning/SKILL.md) for their lifecycle.

## Formatting

- Python/web: `mise exec -- npm run lint` checks Ruff, type-aware ESLint, Astro, and Stylelint. `npm run test:lint` exercises their failure guards.
  Use `mise exec -- npm run format:python` for Python formatting. Keep formatting-only changes separate from behavior changes.
- Swift: `./swiftformat` applies `.swiftformat`; `./swiftformat --lint` checks it. The pre-commit hook formats and re-stages staged Swift files.
- Shell: `./shellcheck` lints tracked shell files by shebang.
- String catalogs must match Xcode serialization. Write them through Xcode or normalize with `./xcstrings`; use `--lint` for checking.

## Writing

Use plain, direct English in documentation, PRs, and responses. Lead with the result or required action.
Prefer familiar words, active voice, and short sentences. Remove filler and repetition; keep technical terms when they improve precision.

## Working in this repo

- **Never commit on `main`.** Branch first (`git checkout -b <name>`). Keep
  every commit for one piece of work on that one branch.
- **Run checks in proportion to risk.** Load [`running-tests`](.agents/skills/running-tests/SKILL.md) to choose the applicable checks.
  Never commit a known-red tree.
- **Multi-step work lands one commit per step**, so history stays bisectable and
  can land piecewise — including pure-groundwork steps, which say so in the body.
- **Commit and push verified work eagerly.** Finished feature work ends with a ready-for-review PR, including work without a formal plan.
  Honor explicit requests to keep work local or uncommitted.

### GitHub

Load the [`github-workflow`](.agents/skills/github-workflow/SKILL.md) skill
for PRs, pushes, review feedback, CI, and posting as the user. Always-on: use
`gh`. Mark AI-posted content. **Addressing review feedback
includes GitHub replies** on the threads you touch — not code-only fixes.

Use [`review-lessons`](.agents/skills/review-lessons/SKILL.md) for the monthly
PR-history audit or an explicit review of recurring failures.
Use [`code-review`](.agents/skills/code-review/SKILL.md) for PR or branch reviews
and the completed-diff review before publication. It owns review procedure and evidence.
`github-workflow` owns publication and replies.
