# Periscope

Periscope is a typed, hierarchical observability stack.
It emits structured `Codable` log events through typed loggers (`Log<Event>`).
Loggers are arranged in a scope tree.
It times work with spans.
It persists to SwiftData so days of history stay queryable on device.
It is browsable from inside the app.

Each module has its own `README.md` with the narrative and API.
This file is the map.

## Modules

- **PeriscopeCore** ([PeriscopeCore/](PeriscopeCore/)) — the model and the
  machinery: events, levels, scopes, links, tags, spans, attachments, the sink
  pipeline (OSLog + SwiftData), ambient event sources, the crash journal, and
  the store. Foundation-level. No SwiftUI.
- **PeriscopeUI** ([PeriscopeUI/](PeriscopeUI/)) — the SwiftUI integration: the
  `logContext` modifier and environment accessors that flow log scopes down a
  view hierarchy. Depends on PeriscopeCore.
- **PeriscopeTools** ([PeriscopeTools/](PeriscopeTools/)) — the on-device
  developer surfaces: the latest-logs viewer, tracer, span views, scope-tree
  browser, debug toast, and inspect mode. Depends on PeriscopeCore, PeriscopeUI,
  and Broadway for styling.

Durability underneath the store comes from
[`JournalKit`](../JournalKit), the generic append-only crash-durable journal.
It is deliberately payload-agnostic, so it knows nothing about log semantics.

[`Prototypes/JournalBenchmark`](Prototypes/JournalBenchmark) is a standalone
macOS benchmark harness that informed the journal design.
It ships in no target and no CI job.

## Build & test

Libraries are declared in the root [`Package.swift`](../../Package.swift).
Their hosted test bundles are in [`Project.swift`](../../Project.swift).
Run `./test PeriscopeCoreTests`, `./test PeriscopeUITests`, or
`./test PeriscopeToolsTests`.

## Open work

Cross-module design and follow-up work for the whole stack is tracked in one
place: [`TODOs.md`](TODOs.md).
