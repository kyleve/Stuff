import Foundation
@testable import InstallerKit
import Testing

@MainActor
struct UpdateServiceTests {
    private typealias F = UpdateFixtures

    @Test func localRemoteAndLocalReinstallsReinterpretTheSameCachedCatalog() async throws {
        let preferences = MemoryUpdatePreferences()
        let catalog = F.withChannels([
            F.browserChannel("main", runs: [2, 1]),
            F.browserChannel("pr-42", runs: [4, 3]),
        ])
        let client = UpdateTestClient(.success(catalog))
        let selection = F.selection(channel: "main", run: 1)
        let local = UpdateService(
            installed: F.localInstalled(status: "dirty"),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let original = try await local.refresh(force: true)
        #expect(original.availability == .local)
        #expect(original.browser.build(for: selection)?.isInstalled == false)
        let remote = UpdateService(
            installed: F.installed(channel: "main"),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        #expect(remote.cached?.availability.needsAttention == true)
        #expect(remote.cached?.browser.build(for: selection)?.isInstalled == true)
        let returned = UpdateService(
            installed: F.localInstalled(status: "unknown"),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let restored = try #require(returned.cached)
        #expect(restored.availability == .local)
        #expect(!restored.availability.needsAttention)
        #expect(restored.browser.build(for: selection)?.isInstalled == false)
        #expect(restored.browser.channels.map(\.id.rawValue) == ["main", "pr-42"])
        #expect(preferences.installerUpdates.cached?.catalog == catalog)
        #expect(await client.calls == 1)
    }

    @Test func rejectsInvalidPersistedCatalogBeforeShowingAnInstallAction() {
        let preferences = MemoryUpdatePreferences()
        preferences.installerUpdates = .init(cached: .init(
            feedURL: F.feedURL,
            checkedAt: F.date,
            catalog: UpdateCatalog(
                schemaVersion: 99,
                apps: F.catalog([2, 1]).apps,
            ),
        ))
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: UpdateTestClient(.success(F.catalog([1]))),
            now: { F.date },
        )
        #expect(service.cached == nil)
        #expect(preferences.installerUpdates.cached == nil)
    }

    @Test func throttlesSuccessfulChecksButManualCheckAlwaysFetches() async throws {
        let preferences = MemoryUpdatePreferences()
        let client = UpdateTestClient(.success(F.catalog([2, 1])))
        var now = F.date
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { now },
        )
        let first = try await service.refresh(force: false)
        now = now.addingTimeInterval(3599)
        #expect(try await service.refresh(force: false) == first)
        #expect(await client.calls == 1)
        _ = try await service.refresh(force: true)
        #expect(await client.calls == 2)
        now = now.addingTimeInterval(3600)
        _ = try await service.refresh(force: false)
        #expect(await client.calls == 3)
    }

    @Test func failurePreservesLastGoodCacheAndDoesNotThrottleRetry() async throws {
        let preferences = MemoryUpdatePreferences()
        let client = UpdateTestClient(.success(F.catalog([2, 1])))
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let original = try await service.refresh(force: true)
        await client.setResult(.failure(.offline))
        await #expect(throws: UpdateTestClient.Failure.self) {
            try await service.refresh(force: true)
        }
        #expect(service.cached == original)
        await client.setResult(.success(F.catalog([3, 2, 1])))
        #expect(try await service.refresh(force: true).availability != original.availability)
    }

    @Test(.timeLimit(.minutes(1)))
    func cachedAutomaticCheckPreservesPendingManualRefresh() async throws {
        let preferences = MemoryUpdatePreferences()
        preferences.installerUpdates = .init(cached: .init(
            feedURL: F.feedURL,
            checkedAt: F.date,
            catalog: F.catalog([1]),
        ))
        let client = HeldUpdateClient()
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let manual = Task { try await service.refresh(force: true) }
        await client.waitForRequests(1)
        #expect(try await service.refresh(force: false).availability == .current)
        await client.resume(0, catalog: F.catalog([2, 1]))
        let updated = try await manual.value
        #expect(updated.availability.needsAttention)
        #expect(service.cached == updated)
    }

    @Test func cachedUpdateRemainsAvailableAcrossLaunchesUntilInstalled() async throws {
        let preferences = MemoryUpdatePreferences()
        let client = UpdateTestClient(.success(F.catalog([2, 1])))
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let snapshot = try await service.refresh(force: true)
        #expect(snapshot.availability.needsAttention)
        let relaunched = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        #expect(relaunched.cached == snapshot)
        let updated = UpdateService(
            installed: F.installed(run: 2),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        #expect(updated.cached?.availability == .current)
    }

    @Test func browserTracksRefreshRetirementAndTheNextInstalledChannel() async throws {
        let preferences = MemoryUpdatePreferences()
        let catalog = F.withChannels([
            F.browserChannel("main", runs: [20]),
            F.browserChannel("pr-42", runs: [10, 9]),
        ])
        let client = UpdateTestClient(.success(catalog))
        let service = UpdateService(
            installed: F.installed(run: 20, channel: "main"),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let selection = F.selection(channel: "pr-42", run: 9)
        let snapshot = try await service.refresh(force: true)
        #expect(snapshot.browser.build(for: selection)?.isInstalled == false)
        #expect(service.cached == snapshot)
        let switched = UpdateService(
            installed: F.installed(run: 9),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        #expect(switched.cached?.browser.build(for: selection)?.isInstalled == true)
        #expect(switched.cached?.availability.needsAttention == true)
        await client.setResult(.success(F.withChannels([
            F.browserChannel("main", runs: [20]),
            F.browserChannel("pr-42", runs: [10, 9], active: false),
        ])))
        let retired = try await service.refresh(force: true)
        #expect(retired.browser.build(for: selection) == nil)
        #expect(service.cached?.browser.channels.map(\.id) == [.main])
    }

    @Test(.timeLimit(.minutes(1))) func cancelledCompletionDoesNotWriteCache() async throws {
        let preferences = MemoryUpdatePreferences()
        let client = HeldUpdateClient()
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let task = Task { try await service.refresh(force: true) }
        await client.waitForRequests(1)
        task.cancel()
        await client.resume(0, catalog: F.catalog([2, 1]))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(preferences.installerUpdates.cached == nil)
    }

    @Test(.timeLimit(.minutes(1))) func olderCompletionCannotOverwriteNewerResponse() async throws {
        let preferences = MemoryUpdatePreferences()
        let client = HeldUpdateClient()
        let service = UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
        let older = Task { try await service.refresh(force: true) }
        await client.waitForRequests(1)
        let newer = Task { try await service.refresh(force: true) }
        await client.waitForRequests(2)
        await client.resume(1, catalog: F.catalog([3, 2, 1]))
        let snapshot = try await newer.value
        await client.resume(0, catalog: F.catalog([2, 1]))
        await #expect(throws: CancellationError.self) { try await older.value }
        #expect(service.cached == snapshot)
    }
}
