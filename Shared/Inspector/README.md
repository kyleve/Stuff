# Inspector

Inspector is a reusable SwiftUI developer runtime for inspecting and deleting an
application's persisted state. An app explicitly configures the resources it
owns; Inspector discovers nothing globally and imports no app code.

The root `InspectorView` uses an adaptive `NavigationSplitView` with three
sections:

- **Files** — lazy directory browsing, hidden items, search, sorting, metadata,
  Quick Look, and confirmed recursive deletion.
- **User Defaults** — persistent-domain values only. Existing strings, booleans,
  integers, floating-point values, dates, and URLs can be edited without
  changing type. Arrays, dictionaries, and data are read-only. Any value can be
  deleted.
- **SwiftData** — generic schema discovery, paged tables, row detail,
  relationship browsing, row/entity deletion, and supported whole-store erase.

It is intended for DEBUG-only boot modes. The host app selects its runtime
before launch and gives Inspector a dedicated `InspectorModeController`, so the
tool can request the regular app for the next process without switching stacks
live. The same dedicated suite carries pending recovery erasures so a fresh
process can finish them before any runtime opens SwiftData.

## Public API

```swift
InspectorView(
    configuration: InspectorConfiguration,
    modeController: InspectorModeController
)

InspectorConfiguration(
    title: String,
    fileContainers: [InspectorConfiguration.FileContainer],
    defaultsDomains: [InspectorConfiguration.DefaultsDomain],
    swiftDataSources: [InspectorConfiguration.SwiftDataSource]
)
```

Each source has a dedicated `Hashable` identifier type. A SwiftData source
provides its storage root, optional exact store URL and explicit model list,
pagination and formatting options, and a factory that opens a `ModelContainer`.
Supplying `storeURL` enables confirmed recovery erasure when the container
cannot open. `recoveryStorageURLs` names exact app-owned files or directories
that must also be discarded to make the source fresh, such as a logging
store's crash-replay journals:

```swift
let configuration = InspectorConfiguration(
    title: "Inspector",
    fileContainers: [
        .init(
            id: .init(rawValue: "documents"),
            title: "Documents",
            rootURL: documentsURL
        ),
    ],
    defaultsDomains: [
        .init(
            id: .init(rawValue: "application"),
            title: "Application",
            userDefaults: .standard,
            persistentDomainName: bundleIdentifier
        ),
    ],
    swiftDataSources: [
        .init(
            id: .init(rawValue: "primary"),
            title: "SwiftData",
            storageRootURL: applicationSupportURL,
            storeURL: AppStore.inspectorStoreURL,
            recoveryStorageURLs: AppStore.inspectorRecoveryStorageURLs,
            modelTypes: AppStore.inspectorModelTypes,
            makeContainer: { try AppStore.makeContainer() }
        ),
    ]
)

let modeController = InspectorModeController(
    applicationIdentifier: bundleIdentifier
)

InspectorView(
    configuration: configuration,
    modeController: modeController
)
```

At DEBUG process boot, call
`completePendingStoreErasures(fileManager:)` before constructing either runtime.
If it returns `false`, construct Inspector so the retained request and error are
available for recovery instead of opening regular application stores.

`InspectorSwiftDataView` and `InspectorSwiftDataConfiguration` remain available
as the focused SwiftData component for previews or other developer surfaces.

## Destructive-operation rules

Inspector never deletes a configured file root. Before file deletion becomes
available, it opens every SwiftData source and obtains the live store URLs. It
then protects each SQLite store, its WAL/SHM/support family, its exact
`recoveryStorageURLs`, and any ancestor whose recursive deletion would contain
them. If a source cannot open, generic file deletion is disabled in its
declared storage tree while unrelated containers remain usable. Canonical-path
checks prevent browsing or recovery through symlinks outside a configured
root.

There is intentionally no file creation, content editing, rename, or move in
v1.

UserDefaults editing is limited to keys already present in a configured
persistent domain. Registration and global domains are not merged in. Writes
are re-read and verified before being reported as successful.

SwiftData mutations run on the same actor as reads. That actor owns the
`ModelContainer`, creates every `ModelContext`, explicitly saves deletions, and
returns only `Sendable` value snapshots and `PersistentIdentifier`s. A complete
erase calls `ModelContainer.erase()` and reopens through the source factory;
raw SQLite deletion remains unavailable for an open store and throughout the
generic file browser.

Every configured SwiftData source remains in the sidebar when its container
cannot open. Inspector shows the opening error instead of entity tables. When
the source declares an exact `storeURL`, a confirmed recovery action deletes
only that database, its WAL/SHM/journal files, and its external-data support
and CloudKit asset directories, including SwiftData's hidden
configuration-named family (for example `.Periscope_SUPPORT` beside
`Periscope.store`). It also deletes each exact
`recoveryStorageURLs` path after verifying that it is a strict, canonical
descendant of the declared storage root. It then removes the source and its
selected detail from the current Inspector session. The configured source may
appear again after relaunch if its factory recreates the store. Similarly named
files remain untouched. Inspector verifies that every declared member is absent
before it dismisses the source and latches the same narrow erasure for the next
process. The host completes that second pass before constructing either
application runtime, preventing a failed store coordinator from recreating a
late SQLite sidecar or auxiliary recovery file after the in-session check. A
failed boot cleanup stays latched, selects Inspector, and surfaces its error
instead of starting the regular runtime against the store. Without an exact URL
the source stays read-only and protected.

Inspector deliberately does not reflectively edit SwiftData attributes.

## SwiftData browsing

Entity discovery can use an explicit `[PersistentModel.Type]` list or fall back
to the container schema. Tables fetch a capped prefix (500 rows by default);
“Load more” re-fetches one longer prefix so offset instability cannot overlap or
skip rows. Binary values render as sizes/placeholders, and relationships are
faulted only after an explicit drill-in.

The small amount of private SwiftData reflection required for generic attribute
and relationship access is isolated in `SwiftDataReflection.swift`.

## Testing

Run:

```sh
./test InspectorTests
./test --snapshots
```

Unit tests use temporary directories, private UserDefaults suites, and in-memory
SwiftData schemas. The module's image references are owned by
`InspectorSnapshotTests` in the repository-wide `StuffSnapshotTests` scheme.
