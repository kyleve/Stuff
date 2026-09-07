# PeriscopeUI

SwiftUI integration for the **Periscope** observability framework ([`PeriscopeCore`](../PeriscopeCore)).
It flows log scopes through the view hierarchy with the `logContext` modifier.
Any view can log with its full context — model and UI — inherited automatically from the environment.

## Installation

`PeriscopeUI` is a local SPM library in this repo (`Shared/Periscope/PeriscopeUI`).
Add it to a target's dependencies in [`Package.swift`](../../../Package.swift):

```swift
.target(name: "YourModule", dependencies: [.target(name: "PeriscopeUI")])
```

## Quick start

Contribute contexts where views are built.
Read them where events happen:

```swift
PhotoDetailView()
    .logContext(model.photo)      // any LogContextProviding model
    .logContext(screenLog)        // or any Log value

struct PhotoDetailView: View {
    @Environment(\.logContext) private var logContext

    var body: some View {
        Button("Save") {
            logContext.info("save tapped")
            let photos = logContext(PhotoLogs.self)
            photos.saved(photoID: .restricted(.identifier, photo.id))
        }
    }
}
```

## Public API

- `View.logContext(_ log: Log<some LogScopeDefinition>)` — contribute a logger's scopes and tags to descendants.
- `View.logContext(_ provider: some LogContextProviding)` — contribute a model object's instance context directly.
- `EnvironmentValues.logContext: LogContext` — the type-erased accumulated context.
  It falls back to a freeform context on `Periscope.shared` outside any modifier.

## How it works

Each `logContext` modifier **links** its context onto whatever enclosing modifiers already contributed (`Log.linked(with:)` semantics).
Stacking modifiers unions scopes and merges tags, with the nearest modifier primary.
The stored accumulator is optional. This prevents the fallback freeform scope from linking into an explicit context.
Deriving typed loggers or emitting events goes through the normal PeriscopeCore API, so nothing here duplicates logging behavior.

## Testing

Swift Testing in [`Tests/`](Tests), hosted in `StuffTestHost` (`PeriscopeUITests` bundle).
Probe views read `\.logContext` and log on appear, hosted via `TestHostSupport.show`, asserted against a private `Periscope` system's recent buffer.
Run with `./test PeriscopeUITests`.
