# PeriscopeUI

SwiftUI integration for the **Periscope** observability framework
([`PeriscopeCore`](../PeriscopeCore)): flow log scopes through the view
hierarchy with the `logContext` modifier, so any view can log with its full
context — model and UI — inherited automatically from the environment.

## Installation

`PeriscopeUI` is a local SPM library in this repo
(`Shared/Periscope/PeriscopeUI`). Add it to a target's dependencies in
[`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeUI")])
```

## Quick start

Contribute contexts where views are built, read them where events happen:

```swift
PhotoDetailView()
    .logContext(model.photo)      // any LogContextProviding model
    .logContext(screenLog)        // or any Log value

struct PhotoDetailView: View {
    @Environment(\.logContext) private var log

    var body: some View {
        Button("Save") {
            log.info("save tapped")             // freeform, full context
            let photos = log(PhotoLogs.self)    // or derive typed loggers
            photos { PhotoLogs.saved }
        }
    }
}
```

## Public API

- `View.logContext(_ log: Log<some LogEvent>)` — contribute a logger's
  scopes and tags to descendants.
- `View.logContext(_ provider: some LogContextProviding)` — contribute a
  model object's instance context directly.
- `EnvironmentValues.logContext: Log<Message>` — the accumulated context;
  falls back to a root logger on `Periscope.shared` outside any modifier.

## How it works

Each `logContext` modifier **links** its context onto whatever enclosing
modifiers already contributed (`Log.linked(with:)` semantics): stacking
modifiers unions scopes and merges tags, with the nearest modifier primary.
The environment value is a plain `Log<Message>` — deriving typed loggers or
emitting events goes through the normal PeriscopeCore API, so nothing here
duplicates logging behavior.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost`
(`PeriscopeUITests` bundle): probe views read `\.logContext` and log on
appear, hosted via `TestHostSupport.show`, asserted against a private
`Periscope` system's recent buffer. Run with `tuist test PeriscopeUITests`.
