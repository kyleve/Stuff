import Foundation
import Inspector
import SnapshotKitTesting
import SwiftData
import SwiftUI
import Testing

/// Pins the complete Inspector sidebar and the SwiftData entity list, over
/// resources built from this module's own fixtures.
///
/// The inspector is app-agnostic, so it is snapshotted that way: a local
/// in-memory schema rather than a host app's. It seeds a fixed row count per
/// entity because the list renders those counts, and it applies no design-system
/// root — the module has none, and the capture should show what a consumer
/// actually gets.
@MainActor
struct InspectorSnapshotTests {
    @Test func inspectorSurfaces() async throws {
        let container = try Self.seededContainer()
        let swiftDataView = NavigationStack {
            InspectorSwiftDataView(
                configuration: InspectorSwiftDataConfiguration(
                    container: container,
                    modelTypes: nil,
                    title: "SwiftData",
                    rowLimit: 500,
                    valueFormatter: nil,
                ),
            )
        }
        // Light is asserted strictly. Dark is quarantined, and the two are
        // separate calls so that quarantine covers only the capture that is
        // actually unreliable — wrapping both would stop guarding the one that
        // has never failed.
        await assertSnapshots(
            of: swiftDataView,
            named: "SwiftData",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light],
            ),
        )

        // The dark capture is bistable: the search field's placeholder renders at
        // one of two widths ~3% apart and only one matches the reference, so this
        // reddens a run perhaps once in several. Quarantined rather than
        // re-recorded, because neither state is more correct than the other and
        // re-recording would just move which one fails.
        //
        // `isIntermittent` because it passes far more often than it fails.
        //
        // What is ruled out, so nobody re-runs these: not a settle-duration
        // problem (captured cold it fails 8/8, and a `settledAtLeast(1.5)` floor
        // still fails 4/4); not the content instance shared across a case's
        // configurations (rebuilding the view per configuration still failed 1 of
        // 6); and not a regression from the commit that first went red, which was
        // docs plus two WhereUI files this bundle doesn't link. See
        // `Shared/Inspector/TODOs.md` for the full evidence and the
        // candidate fix.
        await withKnownIssue(
            "inspectorSurfaces.SwiftData_iPhone_dark is bistable",
            isIntermittent: true,
        ) {
            await assertSnapshots(
                of: swiftDataView,
                named: "SwiftData",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhone],
                    colorSchemes: [.dark],
                ),
            )
        }

        let controlSuiteName = "inspector.snapshot.control"
        let defaultsSuiteName = "inspector.snapshot.defaults"
        let controlDefaults = try #require(UserDefaults(suiteName: controlSuiteName))
        let inspectedDefaults = try #require(UserDefaults(suiteName: defaultsSuiteName))
        defer {
            controlDefaults.removePersistentDomain(forName: controlSuiteName)
            inspectedDefaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        controlDefaults.removePersistentDomain(forName: controlSuiteName)
        inspectedDefaults.removePersistentDomain(forName: defaultsSuiteName)
        inspectedDefaults.set("value", forKey: "example")
        let modeController = InspectorModeController(userDefaults: controlDefaults)
        modeController.enterInspectorOnNextLaunch()

        let rootView = InspectorView(
            configuration: InspectorConfiguration(
                title: "Inspector",
                fileContainers: [
                    .init(
                        id: .init(rawValue: "documents"),
                        title: "Documents",
                        rootURL: FileManager.default.temporaryDirectory,
                    ),
                ],
                defaultsDomains: [
                    .init(
                        id: .init(rawValue: "application"),
                        title: "Application",
                        userDefaults: inspectedDefaults,
                        persistentDomainName: defaultsSuiteName,
                    ),
                ],
                swiftDataSources: [
                    .init(
                        id: .init(rawValue: "swift-data"),
                        title: "Library",
                        storageRootURL: FileManager.default.temporaryDirectory,
                        makeContainer: { try Self.emptyContainer() },
                    ),
                ],
            ),
            modeController: modeController,
        )
        await assertSnapshots(
            of: rootView,
            named: "Root",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
            ),
        )
    }

    /// An in-memory store with a fixed number of rows per entity, so the row
    /// counts the list renders are the same on every run.
    private static func seededContainer() throws -> ModelContainer {
        let schema = Schema([SnapshotAlbum.self, SnapshotTrack.self, SnapshotPlaylist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        let context = container.mainContext
        for index in 0 ..< 3 {
            context.insert(SnapshotAlbum(
                title: "Album \(index)",
                releasedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                trackCount: index + 4,
            ))
        }
        for index in 0 ..< 12 {
            context.insert(SnapshotTrack(title: "Track \(index)", durationSeconds: 120 + index))
        }
        context.insert(SnapshotPlaylist(name: "Favourites"))
        try context.save()
        return container
    }

    private nonisolated static func emptyContainer() throws -> ModelContainer {
        let schema = Schema([SnapshotAlbum.self, SnapshotTrack.self, SnapshotPlaylist.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

// Fixture models. Named distinctly from `InspectorTests`' `Test*`
// models: those live in a different bundle, and two `@Model` classes sharing a
// name would collide in the runtime if both bundles ever loaded into one host
// process.

@Model
final class SnapshotAlbum {
    var title: String?
    var releasedAt: Date?
    var trackCount: Int?

    init(title: String?, releasedAt: Date?, trackCount: Int?) {
        self.title = title
        self.releasedAt = releasedAt
        self.trackCount = trackCount
    }
}

@Model
final class SnapshotTrack {
    var title: String?
    var durationSeconds: Int?

    init(title: String?, durationSeconds: Int?) {
        self.title = title
        self.durationSeconds = durationSeconds
    }
}

@Model
final class SnapshotPlaylist {
    var name: String?

    init(name: String?) {
        self.name = name
    }
}
