# Flagger

Flagger is a scoped feature-flag engine backed by SwiftData. Modules own groups
of typed flags, expose those groups through a source, and the composition root
registers sources without enumerating their flags. Every flag has a default;
only JSON overrides different from that default are stored.

## Declare a group

```swift
public struct MapFlags: FeatureFlagGroup {
    public static let id = FeatureFlagGroupID("map")
    public static let name = "Map"

    public let newRenderer = Flag<Bool, LiveUpdating>(
        "new-renderer",
        name: "New renderer",
        default: true
    )

    public init() {}
}

public extension FeatureFlagGroups {
    var map: MapFlags { self[MapFlags.self] }
}
```

The explicit flag ID is the persisted identity and must survive Swift property
renames. Group properties are discovered once when Flagger opens; the typed
definitions are erased only for persistence and editor metadata.

## Expose and register module sources

```swift
public enum WhereUIFlagSource: FlagSource {
    public static let id = FlagSourceID("where-ui")
    public static let name = "Where UI"
    public static let groups = FeatureFlagGroupRegistry {
        MapFlags.self
    }
}

let sources = FlagSourceRegistry {
    WhereCoreFlagSource.self
    WhereUIFlagSource.self
}
let flagger = try await Flagger.open(
    sources: sources,
    storage: .onDisk(name: "WhereFlags")
)
```

Each Flagger instance owns one scope and physical store. Use distinct instances
for app-wide, logged-in, demo, or other worlds; inject an existing
`ModelContainer` or explicit URL when the host owns store placement.

## Behaviors and access

- `ReadOnceOnLaunch` resolves when Flagger opens.
- `ReadOnceOnFirstAccess` resolves on its first read.
- `LiveUpdating` may be changed and observed while Flagger is alive.

Reads are synchronous from lock-protected state loaded at open. SwiftData opens
and writes remain asynchronous and actor-isolated. Because flags change rarely,
each mutation reloads the complete override store and atomically replaces the
cache with the newest versioned snapshot:

```swift
let enabled = try flagger.value(for: MapFlags().newRenderer)
try await flagger.set(false, for: MapFlags().newRenderer)
for await enabled in flagger.values(for: MapFlags().newRenderer) { /* … */ }
```

`value(for:)` throws decoding failures. `valueOrDefault(for:)` returns the
declared default and emits the failure through `failures()`. A failed frozen
flag stays on its default for that lifetime; repairing its override applies to
the next applicable lifetime.
