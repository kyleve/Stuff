# Stuff – Repository Shape

## Build system

| Tool        | Version  | Pinned via   |
|-------------|----------|--------------|
| Tuist       | 4.200.5  | `.mise.toml` |
| SwiftFormat | 0.60.1   | `.mise.toml` |
| Swift PM    | 6.2      | `Package.swift` (`swift-tools-version`) |

**Libraries** (**StuffCore**, **LifecycleKit**, **WhereCore**, **WhereUI**, **WhereTesting**) are defined in the root [`Package.swift`](Package.swift) — local package for libraries, Tuist for apps and test bundles.

Tuist manifests live at the repo root ([`Project.swift`](Project.swift), [`Tuist.swift`](Tuist.swift)). `Project.swift` references `Package.local(path: .relativeToRoot("."))` and declares the **Where** app, **StuffTestHost**, and unit-test targets that depend on package products.

Run `./ide` (or `./ide -i` to also install dependencies) to regenerate the
Xcode project, install external agent skills, and point Git at `.githooks/`.
Pass `--no-open` to skip launching Xcode (see [Generating the Xcode
project](#generating-the-xcode-project)).

Root dev scripts: `ide`, `swiftformat` (runs SwiftFormat via mise),
`sync-agents` (keeps Claude Code–oriented files in sync with `AGENTS.md`),
`profile` (prints build/test hot spots — slowest build phases, slowest
tests, and slow type-check sites; see `./profile --help`), and `icons`
(adds/removes selectable app icons; see `./icons --help`).

### Managing app icons

`./icons` is the single command for the Where app's alternate icons. It keeps
three things in sync and never edits Swift:

- `Where/Where/Resources/AppIcon.xcassets` — the appiconset iOS swaps to.
- `Where/WhereUI/Sources/Resources/AppIconPreviews.xcassets` — the imageset the
  in-app picker renders (SwiftUI `Image` can't load appiconsets).
- `Where/WhereUI/Sources/Resources/AppIcons.json` — the manifest the picker reads.

```bash
./icons --add art/ocean.png --name Ocean --dark art/ocean-dark.png
./icons --remove ocean
./icons --list
```

Inputs are 1024×1024 PNGs (light required; `--dark` / `--tinted` optional). The
Where target sets `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`, so a new
appiconset is registered automatically — run `./ide --no-open` afterward to
regenerate. The script's file edits work on Linux; compiling the catalogs is
macOS-only. The primary "Classic" icon is reserved.

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

- **Package products** ([`Package.swift`](Package.swift)) — **StuffCore** ([`Shared/StuffCore/Sources/`](Shared/StuffCore/Sources/)) and **LifecycleKit** ([`Shared/LifecycleKit/Sources/`](Shared/LifecycleKit/Sources/)) under [`Shared/`](Shared/); **WhereCore** / **WhereUI** / **WhereTesting** under [`Where/`](Where/).
- **Tuist targets** ([`Project.swift`](Project.swift)) — **Where** app ([`Where/Where/`](Where/Where/)), **StuffTestHost** ([`Shared/StuffTestHost/`](Shared/StuffTestHost/)), **WhereTests** (app tests, no host), and hosted **\*Tests** bundles (**StuffCoreTests**, **LifecycleKitTests**, **WhereCoreTests**, **WhereUITests**) that depend on **StuffTestHost** + **WhereTesting** + the relevant package product.
- Add SPM library targets in `Package.swift` and wire apps/tests in `Project.swift` (see existing `unitTests` helper). A new module also ships a root `README.md` and `AGENTS.md` — see [Per-module docs](#per-module-docs).

## Deployment

| Platform                     | Minimum OS  |
|------------------------------|-------------|
| iPhone, iPad, Mac Catalyst   | iOS 26.0    |
| macOS (native)               | macOS 26.0  |

## Directory layout

Shared code and the shared iOS test host live under **`Shared/`**. Feature apps and their modules (e.g. **Where**) live under a top-level folder per feature (e.g. **`Where/`**).

```
Shared/<TargetName>/
  README.md   – human-facing overview & usage (see Per-module docs)
  AGENTS.md   – agent-facing module shape (see Per-module docs)
  Sources/    – production code
  Tests/      – unit tests (Swift Testing, not XCTest)

<Feature>/<TargetName>/
  README.md
  AGENTS.md
  Sources/
  Tests/
  Resources/  – asset catalogs, etc. (apps only)
```

## Per-module docs

Every module carries two docs at its root, and **a new module must add both**
(use [`Shared/LifecycleKit`](Shared/LifecycleKit/) and
[`Shared/SwiftDataInspector`](Shared/SwiftDataInspector/) as templates):

- `README.md` — the human-facing overview: what the module is, install, a quick
  start, the public API, how it works, and any contracts/limitations.
- `AGENTS.md` — the agent-facing module shape: scope & dependencies, the key
  types, invariants/behaviors to preserve, conventions, and testing patterns. It
  complements this root file (which owns build/format/global rules) and should
  link back to it; it does **not** repeat global rules.

Keep both **current as the code changes** — treat stale docs as a bug. When you
change a module's architecture, public API, conventions, or a documented
behavior, update that module's `README.md` and `AGENTS.md` in the *same* change;
if you change a global rule, a target, or the build/test flow, update this root
`AGENTS.md` too. After adding or renaming an `AGENTS.md`, run `./sync-agents` so
the generated (gitignored) `CLAUDE.md` is produced next to it.

## Conventions

- **Swift Testing** (`import Testing`) for all unit tests – do not use XCTest.
- Generated `.xcodeproj` and `Derived/` are git-ignored; never commit them.
- Bundle IDs follow `com.stuff.<suffix>`.
- Prefer small named structs over tuples for any value with more than
  one field or that escapes a single function — tuples are fine as
  ad-hoc inline returns but should not appear in property types,
  collection element types, or public API.
- Identifiers/keys are `Hashable` (ideally a typed enum) or `AnyHashable`, not
  raw `String`s — a typed token can't silently typo into a new, untracked id,
  and any `Hashable` converts to `AnyHashable` implicitly at the call site.
  (e.g. `LifecycleStep.id` is `AnyHashable`; the Where app keys its launch steps
  with the `LaunchStepID` enum, and `WherePreferences` keys with a `Keys` enum.)
- Don't build closure-based `Binding(get:set:)` values in SwiftUI views; bind
  directly to observable state (`$model.foo`). For a derived binding (e.g.
  mapping an optional error to the `Bool` an `.alert` wants), expose a computed
  `get`/`set` on the `@Observable` model and bind to that, keeping the
  underlying value the single source of truth.
- Don't use a bare `default:` in a `switch` over an enum — enumerate every case
  so adding one is a compile error, not a silent fall-through. For non-frozen
  enums from other modules (e.g. `UNAuthorizationStatus`), handle known cases
  explicitly plus `@unknown default:`, which still flags newly added cases.

## Generating the Xcode project

Agents must never open Xcode on the user's machine — it steals focus and
disrupts the user's session. Always pass `--no-open` when regenerating:

- `./ide --no-open` instead of `./ide`
- `mise exec -- tuist generate --no-open` instead of `tuist generate`

`tuist test` / `tuist build` are CLI-only and do not open Xcode, so no
flag is needed there.

## Acting on requests

The "don't be proactive" rules below scope to *unprompted* actions. A direct
request is itself the go-ahead — carry it to a sensible stopping point rather
than pausing to re-confirm what you were just asked to do.

For non-plan work, leave the tree formatted and the change complete. Commit
when asked or when working a plan; if it's unclear whether you want a commit,
make the change and ask rather than committing silently.

## Working on plans

Multi-step plans (e.g. a `/plan` to-do list) land one commit per to-do so
history stays bisectable and can land piecewise. The loop for each to-do:
mark `in_progress`, implement, run local checks, commit, mark `completed`.

- Branch first: `git rev-parse --abbrev-ref HEAD` must not be `main`/`master`.
  If it is, `git checkout -b <name>` before staging. Branch once; keep every
  commit on it.
- Pre-commit checks are part of "done": `./swiftformat --lint` and the matching
  `tuist test` scheme(s). A red bar means not done — never commit a broken tree.
- Pure-groundwork steps (no behavior change) still get their own commit; say so
  in the body.
- Name the plan step each commit closes (the to-do title is fine).
- Don't push until the user asks — unless the plan says otherwise, or the
  request clearly implies it (e.g. "open a PR", "ship it").

## Working on PR feedback

Don't act on PR review comments (bot or human) that the user hasn't asked you
to address — summarize what's there and ask which to take on. Reading the
comments and surrounding code to write that summary is expected; the gate is on
editing and pushing, not on understanding. Once the user points you at feedback
(names comments, says "address these", etc.), that's your go-ahead — do the
work end to end without re-asking per comment.

## Waiting on CI

Do **not** block the main conversation polling for CI to finish (GitHub
Actions checks, PR mergeability, etc.). After pushing, report what's
running and hand the turn back. If CI genuinely needs to be watched to
completion before continuing, delegate it to a background subagent so
the main conversation stays responsive.

This rule is specific to remote CI. Local commands — `tuist test`,
`swift build`, `./swiftformat --lint`, etc. — should still be awaited
inline in the main conversation.

## Posting on the user's behalf

Anything an agent posts under the user's identity (GitHub PR replies,
issue comments, review responses, Slack messages, etc.) must be
prefixed so the reader knows it was AI-generated, not the user
speaking. Use a short tag like `> _Posted by an AI agent on $USER's
behalf._` as the first line, then the actual content. Do not omit the
prefix even when the comment is short or factual.

## Cursor Cloud specific instructions

Cloud agent VMs run **Linux**, not macOS. This repo targets **iOS 26** with
**Xcode 26+** and **Tuist** (macOS-only). Treat Linux as a partial dev
environment: formatting and agent sync work; builds, tests, and running the
**Where** app require macOS (as in CI on `macos-26`).

### What works on Linux

| Check | Command |
|-------|---------|
| Trust mise config | `mise trust` (once per clone) |
| Install SwiftFormat | `mise install swiftformat@0.60.1` |
| Format lint (CI `format` job equivalent) | `mise exec swiftformat -- swiftformat --lint .` |
| Agent file sync | `./sync-agents` or `./sync-agents --install` |
| Git hooks path | `git config core.hooksPath .githooks` (also done by `./ide`) |

Install **Ruby** if missing (`apt-get install ruby`) — required by `sync-agents`.

### What does not work on Linux

- **Tuist** (`mise install` / `mise install tuist` fails: `unsupported env: linux/amd64`)
- `./ide`, `./swiftformat`, and the pre-commit hook — they call `mise exec -- …`, which tries to install **all** tools from `.mise.toml` including Tuist
- `tuist test`, `tuist build`, iOS Simulator, and running the **Where** app

### Full build & test (macOS only)

Matches CI `.github/workflows/ci.yml`:

```bash
mise install
./ide --no-open
./swiftformat --lint
mise exec -- tuist test --no-selective-testing -- \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
