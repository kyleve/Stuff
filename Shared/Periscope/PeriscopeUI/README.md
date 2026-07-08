# PeriscopeUI

SwiftUI integration for the **Periscope** observability framework
([`PeriscopeCore`](../PeriscopeCore)): flow log scopes through the view
hierarchy with the `logContext` modifier, so any view can log with its full
context — model and UI — inherited automatically from the environment.

> **Status:** scaffolding. The API below lands incrementally; sections are
> filled in as each piece ships.

## Installation

`PeriscopeUI` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeUI`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeUI")])
```

## Public API

Landing incrementally — see the sources for what exists today.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeUITests` bundle). Run with `tuist test PeriscopeUITests`.
