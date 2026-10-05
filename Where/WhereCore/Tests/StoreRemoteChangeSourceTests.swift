import Foundation
import SwiftData
import Testing
@_spi(Testing) @testable import WhereCore

/// The `StoreRemoteChangeSource` seam that makes the CloudKit remote-import path
/// drivable off-device: the scripted double on demand, and a production history
/// observer watching a temporary on-disk store.
struct StoreRemoteChangeSourceTests {
    /// The scripted double yields on `yield()`, so a test can drive the
    /// store-observes-remote-change path deterministically.
    @Test func scriptedSourceYields() async {
        let source = ScriptedStoreRemoteChangeSource()
        let stream = source.remoteChanges

        source.yield()

        #expect(await firstPing(stream, within: .seconds(2)))
    }

    /// A second container over the same file represents a sibling process or
    /// CloudKit import. Its transaction must reach the source without a posted
    /// test notification.
    @Test func historyObserverForwardsExternalAuthorForItsStore() async throws {
        let store = try TemporaryHistoryStore()
        defer { store.remove() }
        let sibling = try store.makeContainer()
        let source = try HistoryObserverRemoteChangeSource(
            modelContainer: store.container,
            localTransactionAuthor: "where-local",
        )
        let stream = source.remoteChanges
        let external = ModelContext(sibling)
        external.author = "where-other-process"
        external.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
        try external.save()

        #expect(await firstPing(stream, within: .seconds(5)))
    }

    /// A commit between the history baseline and observer startup can miss the
    /// observer's first event. The source's catch-up must still forward it.
    @Test func historyObserverCatchesCommitBetweenBaselineAndObservation() async throws {
        let store = try TemporaryHistoryStore()
        defer { store.remove() }
        let sibling = try store.makeContainer()
        let source = try HistoryObserverRemoteChangeSource(
            modelContainer: store.container,
            localTransactionAuthor: "where-local",
            testingAfterHistoryBaseline: {
                let external = ModelContext(sibling)
                external.author = "where-other-process"
                external.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
                try external.save()
            },
        )

        #expect(await firstPing(source.remoteChanges, within: .seconds(5)))
    }

    /// The transaction author prevents local commits from running a second,
    /// full remote reconciliation after their focused one.
    @Test func historyObserverSuppressesItsLocalTransactionAuthor() async throws {
        let store = try TemporaryHistoryStore()
        defer { store.remove() }
        let localAuthor = "where-local"
        let source = try HistoryObserverRemoteChangeSource(
            modelContainer: store.container,
            localTransactionAuthor: localAuthor,
        )
        let stream = source.remoteChanges
        let local = ModelContext(store.container)
        local.author = localAuthor
        local.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
        try local.save()

        #expect(await firstPing(stream, within: .milliseconds(500)) == false)
    }

    /// A separate SwiftData store (Periscope in the app) must not invalidate
    /// Where data or cause a refresh/logging feedback loop.
    @Test func historyObserverIgnoresChangeForAnotherStore() async throws {
        let whereStore = try TemporaryHistoryStore()
        defer { whereStore.remove() }
        let otherStore = try TemporaryHistoryStore()
        defer { otherStore.remove() }
        let source = try HistoryObserverRemoteChangeSource(
            modelContainer: whereStore.container,
            localTransactionAuthor: "where-local",
        )
        let stream = source.remoteChanges
        let other = ModelContext(otherStore.container)
        other.author = "periscope"
        other.insert(SDTrackedRegion(regionID: "us-TX", generationID: .initial))
        try other.save()

        #expect(await firstPing(stream, within: .milliseconds(500)) == false)
    }

    /// Observation tasks must not retain the source past its owner's lifetime.
    @Test func historyObserverSourceFinishesWhenReleased() async throws {
        let store = try TemporaryHistoryStore()
        defer { store.remove() }
        weak var weakSource: HistoryObserverRemoteChangeSource?
        let stream: AsyncStream<Void>

        do {
            let source = try HistoryObserverRemoteChangeSource(
                modelContainer: store.container,
                localTransactionAuthor: "where-local",
            )
            weakSource = source
            stream = source.remoteChanges
        }

        #expect(weakSource == nil)
        #expect(await firstPing(stream, within: .milliseconds(500)) == false)
    }
}

private struct TemporaryHistoryStore {
    let directory: URL
    let container: ModelContainer

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "where-history-observer-\(UUID().uuidString)",
            directoryHint: .isDirectory,
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try Self.makeContainer(in: directory)
    }

    func makeContainer() throws -> ModelContainer {
        try Self.makeContainer(in: directory)
    }

    private static func makeContainer(in directory: URL) throws -> ModelContainer {
        let schema = Schema(SwiftDataStore.inspectorModelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appending(path: "Where.store"),
            cloudKitDatabase: .none,
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func remove() {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record("Could not remove temporary history store: \(error)")
        }
    }
}

/// Awaits the first source emission, returning `false` if none arrives within
/// `budget`. A bounded wait lets rejection tests prove silence without hanging.
private func firstPing(_ stream: AsyncStream<Void>, within budget: Duration) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in stream {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: budget)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
