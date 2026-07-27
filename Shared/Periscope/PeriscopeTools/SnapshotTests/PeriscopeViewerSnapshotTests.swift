import Foundation
@_spi(Testing) import PeriscopeCore
import PeriscopeTools
import SnapshotKitTesting
import SwiftUI
import Testing

/// Pins how the log viewer renders. `PeriscopeViewer` seeds its own
/// `periscopeBroadwayRoot()`, so this captures the tooling's real styling with
/// no host-app root involved — the module owns its own appearance here.
@MainActor
struct PeriscopeViewerSnapshotTests {
    @Test func periscopeViewer() async throws {
        let store = try await Self.frozenStore()
        let viewer = NavigationStack {
            PeriscopeViewer(store: store, title: "Logs")
        }
        await assertSnapshots(
            of: viewer,
            named: "PeriscopeViewer",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
            ),
        )
    }

    /// Fixed "now" the fixture's timestamps hang off, so the rendered log times
    /// don't churn the references every real-world day. Pacific to match the
    /// `TZ` pin the snapshot scheme sets — see `Project.swift`.
    private static let referenceNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!
    }()

    /// A frozen store — fixed records at timestamps pinned around
    /// ``referenceNow`` — rather than the process-global Periscope store, whose
    /// wall-clock timestamps and run-dependent lines would make the image
    /// nondeterministic.
    private static func frozenStore() async throws -> PeriscopeStore {
        let session = LogSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!,
            startedAt: referenceNow.addingTimeInterval(-600),
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
                date: referenceNow.addingTimeInterval(-line.age),
                event: Message(level: line.level, line.text),
                scopes: [line.scope.id],
                tags: [],
            )
        })
        return store
    }
}
