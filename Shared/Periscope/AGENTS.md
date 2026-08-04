# Periscope – Module Group Shape

Periscope is the observability stack: typed `Codable` log events on a scope
tree, spans, ambient sources, a SwiftData store, and the on-device surfaces
that browse it. See [`README.md`](README.md) for the map, and each module's own
`README.md` / `AGENTS.md` for its shape — they are the authority, and this file
does not repeat them.

This file complements the root [`AGENTS.md`](../../AGENTS.md), which owns build,
formatting, and global conventions. Read that first.

## Modules & dependencies

- **PeriscopeCore** — the model and machinery. No SwiftUI, no app code.
- **PeriscopeUI** — SwiftUI integration. Depends on PeriscopeCore.
- **PeriscopeTools** — developer surfaces. Depends on PeriscopeCore,
  PeriscopeUI, and BroadwayCore/BroadwayUI.

Each layer reaches only *down*, and **the Broadway dependency stops at
PeriscopeTools** — Core and UI must stay design-system-free so a consumer can
adopt logging without adopting Broadway.

Durability sits below the stack in [`JournalKit`](../JournalKit), which is
payload-agnostic on purpose: log semantics never leak into it.
[`Prototypes/JournalBenchmark`](Prototypes/JournalBenchmark) is wired into no
target and no CI job.

## Invariants an agent can't re-derive

- **A consumer owns its own root scope; Periscope owns the system.** An app
  declares a facade over a root `Log` scope (Where has `WhereLog`, RegionKit
  `RegionLog`) and emits typed `LogEvent`s through it — never a raw string, and
  never a second logging system. Those separate roots all record into the one
  process-wide `Periscope.shared`, so a single store sink and a single viewer
  see every scope subtree.
- **Attaching the store is the host app's job, once.** `PeriscopeStore.make` is
  `async`; the app bootstraps it at launch and adds it as a sink. Library code
  never attaches one, and processes that shouldn't persist (app extensions)
  simply never get a store — they stay OSLog-only rather than opting out
  somewhere in the framework.
- **The app names the build; Periscope only carries it.** The session the app
  starts the store with supplies `LogSession.attributes` (commit, configuration,
  optimization level — see `LogSessionAttributeKey`). Periscope sits below the
  app modules, so it cannot read a build stamp, and it must not invent one: a
  bundle that wasn't stamped contributes no attributes rather than a build
  called `unknown`. Where fills them from `BuildInfo.logSessionAttributes`.
- **Tests never touch `Periscope.shared`.** Build a fresh system with an
  in-memory store per test and pass it explicitly (`Log<Event>()` defaults to
  `.shared`, so an omitted `system:` silently joins the process-wide one).

## Testing

Hosted Swift Testing bundles (`PeriscopeCoreTests`, `PeriscopeUITests`,
`PeriscopeToolsTests`) run in `StuffTestHost`. 1:1 test files per the root rules.
