# Periscope – Module Group Shape

Periscope is the observability stack. It provides typed `Codable` log events on a scope tree, spans, ambient sources, a SwiftData store, and on-device surfaces that browse it. See [`README.md`](README.md) for the map. Each module's own `README.md` / `AGENTS.md` is the authority. This file does not repeat them.

Read the root [`AGENTS.md`](../../AGENTS.md) first. That file owns build, formatting, and global conventions.

## Modules & dependencies

- **PeriscopeMacros** — compile-time event generation. Depends on SwiftSyntax and runs only on the build host.
- **PeriscopeCore** — the model and machinery. No SwiftUI, no app code.
- **PeriscopeUI** — SwiftUI integration. Depends on PeriscopeCore.
- **PeriscopeTools** — developer surfaces. Depends on PeriscopeCore, PeriscopeUI, BroadwayCore/BroadwayUI, and SFSafeSymbols.

Each layer reaches only down. **The Broadway dependency stops at PeriscopeTools.** Core and UI must stay design-system-free so a consumer can adopt logging without adopting Broadway.

Durability sits below the stack in [`JournalKit`](../JournalKit). It is payload-agnostic on purpose. Log semantics must never leak into it.

[`Prototypes/JournalBenchmark`](Prototypes/JournalBenchmark) is wired into no target and no CI job.

## Invariants an agent can't re-derive

- **A consumer owns its own root scope. Periscope owns the system.**
- **An app declares a facade over a root `Log` scope** (Where has `WhereLog`, RegionKit `RegionLog`).
- **Declare repository events with `@LogScope`, `@LogEvent`, and `@LogField`.** Emit them through generated classified methods. Never write a direct `LogEvent` conformance.
- **Those separate roots all record into the one process-wide `Periscope.shared`.**
- **Then a single store sink and a single viewer see every scope subtree.**
- **Attaching the store is the host app's job, once.** `PeriscopeStore.make` is `async`.
- **The app bootstraps it at launch and adds it as a sink.** Library code never attaches one.
- **Processes that must not persist (app extensions) simply never get a store.** They stay OSLog-only rather than opting out somewhere in the framework.
- **The app names the build. Periscope only carries it.**
- **The session the app starts the store with supplies `LogSession.attributes`.** That covers commit, configuration, and optimization level — see `LogSessionAttributeKey`.
- **Periscope sits below the app modules.** It cannot read a build stamp. It must not invent one.
- **A bundle that was not stamped contributes no attributes rather than a build called `unknown`.**
- **Where fills them from `BuildInfo.logSessionAttributes`.**
- **Tests never touch `Periscope.shared`.** Build a fresh system with an in-memory store per test. Pass it explicitly.
- **`Log<Scope>()` defaults to `.shared`.** An omitted `system:` silently joins the process-wide one.

## Testing

Hosted Swift Testing bundles (`PeriscopeCoreTests`, `PeriscopeUITests`, `PeriscopeToolsTests`) run in `StuffTestHost`. Use 1:1 test files per the root rules.
