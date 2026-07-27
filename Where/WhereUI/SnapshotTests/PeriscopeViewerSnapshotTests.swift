@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SnapshotKitTesting
import SwiftUI
import Testing
@testable import WhereUI

/// Pins the log viewer the developer tools push. It lives in PeriscopeTools
/// rather than WhereUI, but it's captured here because this is where it's
/// reachable in the app, and the capture goes through Where's Broadway root so
/// it renders with app styling.
@MainActor
struct PeriscopeViewerSnapshotTests {
    @Test func periscopeViewer() async throws {
        let store = try await Self.frozenStore()
        let viewer = NavigationStack {
            PeriscopeViewer(store: store, title: "Logs")
        }
        .whereBroadwayRoot()
        await assertSnapshots(
            of: viewer,
            named: "PeriscopeViewer",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
            ),
        )
    }

    /// A frozen store — fixed records at timestamps pinned around
    /// `PreviewSupport.referenceNow` — rather than the process-global Periscope
    /// store, whose wall-clock timestamps and run-dependent lines would make the
    /// image nondeterministic.
    private static func frozenStore() async throws -> PeriscopeStore {
        let session = LogSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            startedAt: PreviewSupport.referenceNow.addingTimeInterval(-600),
            appVersion: "1.0",
            buildNumber: "1",
            osVersion: "iOS 26.0",
            deviceModel: "iPhone17,1",
        )
        let store = try await PeriscopeStore.inMemory(session: session)

        let root = LogScope.root(named: "where")
        let launch = root.child(named: "launch")
        let store_ = root.child(named: "store")
        let location = root.child(named: "location")
        let backup = root.child(named: "backup")
        await store.defineScopes([root, launch, store_, location, backup])

        // Seconds before `referenceNow` each line was "logged".
        let lines: [(level: LogLevel, scope: LogScope, text: String, age: TimeInterval)] = [
            (.info, launch, "Launch sequence completed in 412ms.", 347),
            (.debug, store_, "Committed 3 day records in one transaction.", 289),
            (.notice, root, "Rebuilt the attributor for 4 tracked regions.", 214),
            (.warning, location, "Skipped a sample with poor horizontal accuracy (312m).", 158),
            (.error, backup, "Backup export failed: the archive directory is unwritable.", 96),
            (.info, root, "Year report refreshed for 2026.", 41),
        ]
        await store.write(lines.map { line in
            LogRecord(
                date: PreviewSupport.referenceNow.addingTimeInterval(-line.age),
                event: Message(level: line.level, line.text),
                scopes: [line.scope.id],
                tags: [],
            )
        })
        return store
    }
}
