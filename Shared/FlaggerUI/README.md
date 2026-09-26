# FlaggerUI

FlaggerUI supplies the observable environment model and searchable editor for a
Flagger scope.

```swift
@State private var flaggerModel = FlaggerModel(flagger)

RootView()
    .environment(flaggerModel)
```

Modules add environment-style accessors to `FeatureFlagGroups`; FlaggerModel
and `FlagGroupAccessor` turn those key paths into typed values:

```swift
public extension FeatureFlagGroups {
    var map: MapFlags { self[MapFlags.self] }
}

struct MapView: View {
    @Environment(FlaggerModel.self) private var flagger

    var body: some View {
        if flagger.map.newRenderer {
            NewMapView()
        }
    }
}
```

Live writes are explicit and asynchronous:

```swift
try await flagger.map.set(false, for: \.newRenderer)
```

`FlaggerEditorView` uses the injected model. It groups flags by source and
group, searches metadata, toggles Booleans, validates other Codable values as
JSON, resets defaults, marks invalid overrides, and labels frozen edits as
applying next lifetime.
