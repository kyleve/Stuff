# Stuff – Repository Shape

## Build system

| Tool        | Version | Pinned via   |
|-------------|---------|--------------|
| Tuist       | 4.40.0  | `.mise.toml` |
| SwiftFormat | 0.60.1  | `.mise.toml` |

Tuist manifests live at the repo root (`Project.swift`, `Tuist.swift`).
Run `./ide` (or `./ide -i` to also install dependencies) to regenerate the
Xcode project, install external agent skills, and point Git at `.githooks/`.

Root dev scripts: `ide`, `swiftformat` (runs SwiftFormat via mise), and
`sync-agents` (keeps Claude Code–oriented files in sync with `AGENTS.md`).

## Formatting

- **SwiftFormat** uses [`.swiftformat`](.swiftformat). Run `./swiftformat` to
  format the tree, or `./swiftformat --lint` to check only (as in CI).
- The pre-commit hook (enabled by `./ide` via `core.hooksPath`) formats staged
  `*.swift` files in place and re-stages them.

## Agent instructions sync

`AGENTS.md` is the source of truth for AI agent instructions. Cursor reads
`AGENTS.md` natively; Claude Code uses `CLAUDE.md` and `.claude/skills/`.
Generated files (`CLAUDE.md`, `.claude/skills/`) are gitignored and produced
by `./sync-agents`.

- `./sync-agents` — generate `CLAUDE.md` next to each `AGENTS.md` and mirror
  `.agents/skills/` into `.claude/skills/`.
- `./sync-agents --install` — fetch external skills listed in
  `.agents/external-skills.json` (run automatically by `./ide`).
- `./sync-agents --add <url> [name]` — add an external skill from GitHub.
- `./sync-agents --update` — re-fetch all external skills to the latest commit.

## Targets

- **StuffCore** — macOS framework for shared code (`StuffCore/Sources/`), with unit tests under `StuffCore/Tests/` (Swift Testing).
- Add more targets in `Project.swift` using `macApp()` or `framework()` helpers.

## Deployment

| Platform                     | Minimum OS  |
|------------------------------|-------------|
| iPhone, iPad, Mac Catalyst   | iOS 26.0    |
| macOS (native)               | macOS 26.0  |

## Directory layout

```
<TargetName>/
  Sources/    – production code
  Tests/      – unit tests (Swift Testing, not XCTest)
  Resources/  – asset catalogs, etc. (apps only)
```

## Conventions

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- Generated `.xcodeproj` and `Derived/` are git-ignored; never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

## Plans

Implementation plans go in `Plans/` and are named
`<NNN>-<YYYY-MM-DD>-<slug>.md`.
