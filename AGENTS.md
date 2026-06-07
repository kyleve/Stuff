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
Pass `--no-open` (e.g. `./ide --no-open`) to regenerate without launching
Xcode — useful from a terminal where you don't want the IDE to grab focus.

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
- Prefer small named structs over tuples for any value with more than
  one field or that escapes a single function — tuples are fine as
  ad-hoc inline returns but should not appear in property types,
  collection element types, or public API.

## Generating the Xcode project

Agents must never open Xcode on the user's machine — it steals focus and
disrupts the user's session. Always pass `--no-open` when regenerating:

- `./ide --no-open` instead of `./ide`
- `mise exec -- tuist generate --no-open` instead of `tuist generate`

`tuist test` / `tuist build` are CLI-only and do not open Xcode, so no
flag is needed there.

## Working on plans

When implementing a multi-step plan (e.g. the to-do list produced by a
`/plan` invocation), commit after each step once its local checks
pass — one commit per to-do, with the test/lint run baked into the
"definition of done" for that step. This keeps history bisectable and
lets the plan land piecewise if a later step regresses.

Before the first commit, check out a dedicated feature branch — never
commit plan work directly onto `main` (or `master`). If you're still on
the base branch, run `git checkout -b <descriptive-name>` first. Branch
once at the start of the plan and keep every step's commit on it.

The loop for each to-do is: mark `in_progress`, implement the change,
run the relevant local checks, commit, mark `completed`, move on.

- Before committing the first to-do, confirm you're on a feature branch
  (`git rev-parse --abbrev-ref HEAD` should not be `main`/`master`); if
  it is, create one before staging anything.

- Required pre-commit checks: `./swiftformat --lint` and the matching
  `tuist test` scheme(s). A red bar means the step is not done — fix
  it before committing, do not stage a broken tree.
- If a step is pure groundwork (no behavior change, nothing
  meaningful to test), still commit it on its own so the next step's
  diff stays focused; say so in the commit body.
- Each commit message should name the plan step it closes (matching
  the to-do title is fine) so the chain is readable end-to-end.
- Do not push until the user asks, unless the plan explicitly says
  otherwise.

## Working on PR feedback

Do **not** proactively act on PR review comments (bot or human). When new
comments appear, summarize what's there and ask which ones to address
before reading more context, editing files, or pushing commits. Wait for
explicit go-ahead — either the user asking you to handle the feedback,
or you asking and getting permission first.

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

On macOS, use the normal `./swiftformat --lint` and `mise exec -- tuist test` flow from the README.

### Full build & test (macOS only)

Matches CI `.github/workflows/ci.yml`:

```bash
mise install
./ide --no-open
./swiftformat --lint
mise exec -- tuist test --no-selective-testing -- \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'
```
