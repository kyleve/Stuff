# PeriscopeTools

On-device log exploration for the **Periscope** observability framework
([`PeriscopeCore`](../PeriscopeCore)): a searchable latest-logs viewer, a
tracer that follows an error back through time and up the scope tree, a
hookable debug toast for warnings and errors, and a "log view mode" that
reveals the events behind any wrapped view.

> **Status:** the viewer has landed; the tracer, toast, and log view mode
> land incrementally.

## Installation

`PeriscopeTools` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeTools`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeTools")])
```

## Public API

Landing incrementally — see the sources for what exists today.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeToolsTests` bundle). Run with `tuist test PeriscopeToolsTests`.
