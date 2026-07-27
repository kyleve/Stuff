import Foundation
import SnapshotKitTesting
import SwiftData
import SwiftDataInspector
import SwiftUI
import Testing

/// Pins how the root entity list renders, over a store built from this
/// module's own fixtures.
///
/// The inspector is app-agnostic, so it is snapshotted that way: a local
/// in-memory schema rather than a host app's. It seeds a fixed row count per
/// entity because the list renders those counts, and it applies no design-system
/// root — the module has none, and the capture should show what a consumer
/// actually gets.
@MainActor
struct SwiftDataInspectorSnapshotTests {
    @Test func swiftDataInspector() async throws {
        let container = try Self.seededContainer()
        let view = NavigationStack {
            SwiftDataInspectorView(
                configuration: SwiftDataInspectorConfiguration(
                    container: container,
                    modelTypes: nil,
                    title: "SwiftData",
                    rowLimit: 500,
                    valueFormatter: nil,
                ),
            )
        }
        await assertSnapshots(
            of: view,
            named: "SwiftDataInspector",
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
}

// Fixture models. Named distinctly from `SwiftDataInspectorTests`' `Test*`
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
