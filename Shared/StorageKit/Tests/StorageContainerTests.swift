import Foundation
@testable import StorageKit
import SwiftData
import Testing

struct StorageContainerTests {
    // MARK: - Tree

    @Test
    func vendsAndCachesChildContainers() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let logs = try await user.container("logs")
        let logsAgain = try await user.container("logs")

        #expect(logs === logsAgain)
        #expect(logs.url == user.url.appending(path: "logs", directoryHint: .isDirectory))
        #expect(FileManager.default.fileExists(atPath: logs.url.path))
    }

    @Test
    func vendsANestedPath() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let leaf = try await user.container(path: ["logs", "today"])

        #expect(leaf.key == "today")
        #expect(leaf.url == user.url
            .appending(path: "logs", directoryHint: .isDirectory)
            .appending(path: "today", directoryHint: .isDirectory))
        #expect(FileManager.default.fileExists(atPath: leaf.url.path))
    }

    @Test
    func fileURLPointsIntoTheContainerDirectory() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let fileURL = user.fileURL("note.txt")
        try Data("hello".utf8).write(to: fileURL)

        #expect(fileURL == user.url.appending(path: "note.txt", directoryHint: .notDirectory))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "hello")
    }

    // MARK: - Key-value store

    @Test
    func inMemoryKeyValueStoresAreNamespacedPerContainerAndCached() async throws {
        let system = try StorageSystem("Where", mode: .inMemory)
        let a = try await system.container("a")
        let b = try await system.container("b")

        let aStore = await a.keyValueStore()
        let bStore = await b.keyValueStore()
        aStore.set(true, forKey: "flag")

        #expect(aStore.bool(forKey: "flag"))
        #expect(!bStore.bool(forKey: "flag"))
        #expect(await a.keyValueStore() === aStore)
    }

    @Test
    func persistentKeyValueStoreRoundTripsAndIsPurgedOnDelete() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        await user.keyValueStore().set(99, forKey: "count")
        #expect(await user.keyValueStore().integer(forKey: "count") == 99)

        try await user.deleteContainer()

        let revived = try await system.container("user-1")
        #expect(await revived.keyValueStore().integer(forKey: "count") == 0)

        try await system.deleteAll()
    }

    // MARK: - SwiftData

    @Test
    func persistentModelContainerIsolatesItsStoreAndCaches() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let container = try await user.modelContainer(for: [Note.self])
        let again = try await user.modelContainer(for: [Note.self])
        #expect(container === again)

        let context = ModelContext(container)
        context.insert(Note(text: "hi"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)

        let storeDir = user.url.appending(path: "store", directoryHint: .isDirectory)
        let storeFile = storeDir.appending(path: "store.store", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: storeFile.path))
    }

    @Test
    func inMemoryModelContainerWritesNoStoreFile() async throws {
        let system = try StorageSystem("Where", mode: .inMemory)
        let user = try await system.container("user-1")
        let container = try await user.modelContainer(for: [Note.self])

        let context = ModelContext(container)
        context.insert(Note(text: "hi"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Note>()) == 1)

        let storeDir = user.url.appending(path: "store", directoryHint: .isDirectory)
        let storeFile = storeDir.appending(path: "store.store", directoryHint: .notDirectory)
        #expect(!FileManager.default.fileExists(atPath: storeFile.path))
        // In-memory mode must not touch disk at all — not even the store directory.
        #expect(!FileManager.default.fileExists(atPath: storeDir.path))

        try await system.deleteAll()
    }

    @Test
    func modelContainerIsRecreatedAfterDeleteContents() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let first = try await user.modelContainer(for: [Note.self])
        let writeContext = ModelContext(first)
        writeContext.insert(Note(text: "hi"))
        try writeContext.save()
        #expect(try writeContext.fetchCount(FetchDescriptor<Note>()) == 1)

        try await user.deleteContents()

        // The store's files were deleted; re-vending must rebuild a fresh container
        // rather than hand back the stale cached one pointing at deleted files.
        let second = try await user.modelContainer(for: [Note.self])
        #expect(second !== first)
        let readContext = ModelContext(second)
        #expect(try readContext.fetchCount(FetchDescriptor<Note>()) == 0)
    }

    @Test
    func reVendingAStoreWithDifferentTypesThrows() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let first = try await user.modelContainer(for: [Note.self])

        // Same name, different schema → caught, not silently the wrong container.
        await #expect(throws: StorageError.modelStoreSchemaMismatch("store")) {
            _ = try await user.modelContainer(for: [Note.self, Tag.self])
        }

        // The same type set still returns the cached container.
        let again = try await user.modelContainer(for: [Note.self])
        #expect(again === first)
    }

    // MARK: - Deactivate

    @Test
    func deactivateRunsHandlersChildrenFirstAndKeepsData() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let logs = try await user.container("logs")
        let file = logs.fileURL("a.txt")
        try Data("x".utf8).write(to: file)

        let log = CallLog()
        await user.onDeactivate { await log.record("user") }
        await logs.onDeactivate { await log.record("logs") }

        try await user.deactivate()

        #expect(await log.entries == ["logs", "user"])
        #expect(await user.state == .inactive)
        #expect(await logs.state == .inactive)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func reVendingReactivatesAnInactiveContainer() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        _ = try await user.container("logs")
        try await user.deactivate()
        #expect(await user.state == .inactive)

        let logs = try await user.container("logs")
        #expect(await user.state == .active)
        #expect(FileManager.default.fileExists(atPath: logs.url.path))
    }

    @Test
    func deactivateIsANoOpWhenAlreadyInactive() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let log = CallLog()
        await user.onDeactivate { await log.record("user") }

        try await user.deactivate()
        try await user.deactivate()

        #expect(await log.entries == ["user"])
    }

    @Test
    func deregisterStopsAHandlerFromFiring() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let log = CallLog()
        let token = await user.onDeactivate { await log.record("user") }
        await user.deregister(token)

        try await user.deactivate()
        #expect(await log.entries.isEmpty)
    }

    // MARK: - Delete

    @Test
    func deleteContainerRunsPhasesInOrderChildrenFirst() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let logs = try await user.container("logs")
        let log = CallLog()
        for (container, label) in [(user, "user"), (logs, "logs")] {
            await container.prepareForDeletion { await log.record("prepare:\(label)") }
            await container.onDeactivate { await log.record("deactivate:\(label)") }
            await container.afterDeletion { await log.record("after:\(label)") }
        }

        try await user.deleteContainer()

        #expect(await log.entries == [
            "prepare:logs",
            "prepare:user",
            "deactivate:logs",
            "deactivate:user",
            "after:logs",
            "after:user",
        ])
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
    }

    @Test
    func deleteContainerLeavesSiblingsAndDeregisters() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user1 = try await system.container("user-1")
        let user2 = try await system.container("user-2")
        let logs1 = try await user1.container("logs")

        try await user1.deleteContainer()

        #expect(!FileManager.default.fileExists(atPath: user1.url.path))
        #expect(FileManager.default.fileExists(atPath: user2.url.path))
        #expect(await user1.state == .deleted)
        #expect(await logs1.state == .deleted)

        await #expect(throws: StorageError.self) { _ = try await user1.container("x") }
        await #expect(throws: StorageError.self) { _ = try await logs1.container("x") }

        let user1Revived = try await system.container("user-1")
        #expect(user1Revived !== user1)
        #expect(FileManager.default.fileExists(atPath: user1Revived.url.path))
    }

    @Test
    func deletingAnAlreadyDeactivatedNodeRunsOnDeactivateOnce() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let logs = try await user.container("logs")
        let log = CallLog()
        await user.onDeactivate { await log.record("user") }
        await logs.onDeactivate { await log.record("logs") }

        try await user.deactivate()
        #expect(await log.entries == ["logs", "user"])

        try await user.deleteContainer()

        // The delete must not re-fire onDeactivate — it already ran on deactivate.
        #expect(await log.entries == ["logs", "user"])
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
    }

    @Test
    func vendingIsRejectedWhileTeardownIsInFlight() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let outcome = VendOutcome()
        // A handler running mid-teardown tries to vend onto the node being deleted;
        // it must be rejected rather than resurrecting the directory.
        await user.prepareForDeletion {
            do {
                _ = try await user.container("sneaky")
                await outcome.record(rejected: false)
            } catch {
                await outcome.record(rejected: true)
            }
        }

        try await user.deleteContainer()

        #expect(await outcome.wasRejected == true)
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
        let sneaky = user.url.appending(path: "sneaky", directoryHint: .isDirectory)
        #expect(!FileManager.default.fileExists(atPath: sneaky.path))
    }

    // MARK: - Park-safe retries

    @Test
    func throwingPrepareForDeletionParksWithNothingDeleted() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let throwOnce = ThrowOnce()
        await user.prepareForDeletion { try await throwOnce.fireIfArmed() }

        await #expect(throws: StorageTestError.self) { try await user.deleteContainer() }
        #expect(FileManager.default.fileExists(atPath: user.url.path))

        try await user.deleteContainer()
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
    }

    @Test
    func throwingOnDeactivateParksWithNothingDeleted() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let throwOnce = ThrowOnce()
        await user.onDeactivate { try await throwOnce.fireIfArmed() }

        await #expect(throws: StorageTestError.self) { try await user.deleteContainer() }
        #expect(FileManager.default.fileExists(atPath: user.url.path))

        try await user.deleteContainer()
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
    }

    @Test
    func parkedDeleteOfAnInactiveNodeRevertsToInactive() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        try await user.deactivate()
        #expect(await user.state == .inactive)

        let throwOnce = ThrowOnce()
        await user.prepareForDeletion { try await throwOnce.fireIfArmed() }

        await #expect(throws: StorageTestError.self) { try await user.deleteContainer() }

        // A parked delete restores the exact prior resting state, not just `active`.
        #expect(await user.state == .inactive)
        #expect(FileManager.default.fileExists(atPath: user.url.path))
    }

    @Test
    func throwingAfterDeletionIsPostCommitAndRetriesOnlyThatStep() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let throwOnce = ThrowOnce()
        await user.afterDeletion { try await throwOnce.fireIfArmed() }

        await #expect(throws: StorageTestError.self) { try await user.deleteContainer() }
        // Deletion already stands — the files are gone despite the throw.
        #expect(!FileManager.default.fileExists(atPath: user.url.path))
        #expect(await user.state == .deleted)

        // Retry re-runs only the post-commit step; it no longer throws.
        try await user.deleteContainer()
    }

    @Test
    func reVendingAfterAFailedAfterDeletionGivesAFreshContainer() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let throwOnce = ThrowOnce()
        await user.afterDeletion { try await throwOnce.fireIfArmed() }

        await #expect(throws: StorageTestError.self) { try await user.deleteContainer() }
        #expect(await user.state == .deleted)

        // Despite the afterDeletion throw, the node was deregistered from its
        // parent, so re-vending the key builds a fresh, usable container rather
        // than handing back the deleted one.
        let fresh = try await system.container("user-1")
        #expect(fresh !== user)
        #expect(FileManager.default.fileExists(atPath: fresh.url.path))
        _ = try await fresh.container("logs")
    }

    // MARK: - deleteContents

    @Test
    func deleteContentsClearsDescendantsAndFilesButKeepsTheNode() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let logs = try await user.container("logs")
        let loose = user.fileURL("note.txt")
        try Data("x".utf8).write(to: loose)

        try await user.deleteContents()

        #expect(!FileManager.default.fileExists(atPath: logs.url.path))
        #expect(!FileManager.default.fileExists(atPath: loose.path))
        #expect(FileManager.default.fileExists(atPath: user.url.path))
        #expect(await user.state == .active)

        let logsRevived = try await user.container("logs")
        #expect(FileManager.default.fileExists(atPath: logsRevived.url.path))
    }

    // MARK: - Error surfacing

    @Test
    func deletionErrorsSurfaceAndLeaveDataInPlace() async throws {
        let temp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let system = try StorageSystem("Where", mode: .persistent, base: .custom(temp))

        let user = try await system.container("user-1")
        let parent = system.url
        // A read-only parent directory makes removing `user` fail.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: parent.path,
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: parent.path,
            )
        }

        await #expect(throws: (any Error).self) { try await user.deleteContainer() }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: parent.path,
        )
        #expect(FileManager.default.fileExists(atPath: user.url.path))
    }
}
