# Stuff – Repository Shape

## Build system

| Tool        | Version | Pinned via   |
|-------------|---------|--------------|
| Tuist       | 4.40.0  | `.mise.toml` |
| SwiftFormat | 0.60.1  | `.mise.toml` |
| Swift PM    | 6.2     | `Package.swift` (`swift-tools-version`) |

**Libraries** (**StuffCore**, **WhereCore**, **WhereUI**, **WhereTesting**) are defined in the root [`Package.swift`](Package.swift) (same pattern as Broadway: local package + Tuist for apps and test bundles).

Tuist manifests live at the repo root ([`Project.swift`](Project.swift), [`Tuist.swift`](Tuist.swift)). `Project.swift` references `Package.local(path: .relativeToRoot("."))` and declares the **Where** app, **StuffTestHost**, and unit-test targets that depend on package products.

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

- **Package products** ([`Package.swift`](Package.swift)) — **StuffCore** ([`Shared/StuffCore/Sources/`](Shared/StuffCore/Sources/)), **WhereCore** / **WhereUI** / **WhereTesting** under [`Where/`](Where/).
- **Tuist targets** ([`Project.swift`](Project.swift)) — **Where** app ([`Where/Where/`](Where/Where/)), **StuffTestHost** ([`Shared/StuffTestHost/`](Shared/StuffTestHost/)), **WhereTests** (app tests, no host), and hosted **\*Tests** bundles (**StuffCoreTests**, **WhereCoreTests**, **WhereUITests**) that depend on **StuffTestHost** + **WhereTesting** + the relevant package product.
- Add SPM library targets in `Package.swift` and wire apps/tests in `Project.swift` (see existing `unitTests` helper).

## Deployment

| Platform                     | Minimum OS  |
|------------------------------|-------------|
| iPhone, iPad, Mac Catalyst   | iOS 26.0    |
| macOS (native)               | macOS 26.0  |

## Directory layout

Shared code and the shared iOS test host live under **`Shared/`**. Feature apps and their modules (e.g. **Where**) live under a top-level folder per feature (e.g. **`Where/`**).

```
Shared/<TargetName>/
  Sources/    – production code
  Tests/      – unit tests (Swift Testing, not XCTest)

<Feature>/<TargetName>/
  Sources/
  Tests/
  Resources/  – asset catalogs, etc. (apps only)
```

## Conventions

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- Generated `.xcodeproj` and `Derived/` are git-ignored; never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.

## Plans

Implementation plans go in `Plans/` and are named
`<NNN>-<YYYY-MM-DD>-<slug>.md`.
