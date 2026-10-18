import Foundation
@testable import InstallerKit
import Testing

@MainActor
struct UpdateModelTests {
    private typealias F = UpdateFixtures

    @Test func badgeRemainsAcrossLaunchesAndRefreshes() async {
        let preferences = MemoryUpdatePreferences()
        let client = UpdateModelClient(F.catalog([2, 1]))
        let service = makeService(preferences, client: client)
        let model = UpdateModel(service: service)
        await model.refresh(force: true)
        #expect(model.needsAttention)
        #expect(UpdateModel(service: service).needsAttention)
        await model.refresh(force: false)
        #expect(model.needsAttention)
    }

    @Test func failedManualCheckKeepsLastResultAndOriginalError() async {
        let client = UpdateModelClient(F.catalog([2, 1]))
        let model = UpdateModel(service: makeService(
            MemoryUpdatePreferences(),
            client: client,
        ))
        await model.refresh(force: true)
        let last = model.state.snapshot
        client.result = .failure(.offline)
        await model.refresh(force: true)
        guard case let .failed(error, previous) = model.state
        else { Issue.record("Expected a failure"); return }
        #expect(error is UpdateModelClient.Failure)
        #expect(previous == last)
        #expect(model.needsAttention)
        #expect(!model.isChecking)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func cachedAutomaticCheckPreservesPendingManualRefresh(fails: Bool) async {
        let client = UpdateModelClient(F.catalog([1]))
        let service = makeService(MemoryUpdatePreferences(), client: client)
        let model = UpdateModel(service: service)
        await model.refresh(force: false)
        let previous = model.state.snapshot

        client.held = true
        let manual = Task { await model.refresh(force: true) }
        await client.waitForRequests(1)
        await model.refresh(force: false)
        #expect(model.isChecking)
        #expect(client.fetchCount == 2)
        if fails {
            client.resume(0, error: .offline)
        } else {
            client.resume(0, catalog: F.catalog([2, 1]))
        }
        await manual.value

        #expect(!model.isChecking)
        if fails {
            guard case let .failed(error, snapshot) = model.state
            else { Issue.record("Expected the manual check's failure"); return }
            #expect(error is UpdateModelClient.Failure)
            #expect(snapshot == previous)
            #expect(service.cached == previous)
        } else {
            #expect(model.needsAttention)
            #expect(service.cached?.availability.needsAttention == true)
        }
    }

    @Test(.timeLimit(.minutes(1))) func foregroundReentrySupersedesCancelledCheck() async {
        let client = UpdateModelClient(F.catalog([2, 1]))
        client.held = true
        let model = UpdateModel(service: makeService(
            MemoryUpdatePreferences(),
            client: client,
        ))
        let first = Task { await model.refresh(force: false) }
        await client.waitForRequests(1)
        first.cancel()
        let second = Task { await model.refresh(force: false) }
        await client.waitForRequests(2)
        client.resume(1, catalog: F.catalog([2, 1]))
        await second.value
        client.resume(0, catalog: F.catalog([1]))
        await first.value
        #expect(model.needsAttention)
        #expect(!model.isChecking)
    }

    @Test func retirementHasAnActionableBadgeWhileCurrentAndMissingChannelsDoNot() {
        for catalog in [
            F.catalog([1], active: false),
            F.catalog([1]),
            UpdateCatalog(schemaVersion: 3, apps: []),
        ] {
            let preferences = MemoryUpdatePreferences()
            preferences.installerUpdates = .init(cached: .init(
                feedURL: F.feedURL,
                checkedAt: F.date,
                catalog: catalog,
            ))
            let model = UpdateModel(service: makeService(
                preferences,
                client: UpdateModelClient(catalog),
            ))
            #expect(model.needsAttention == catalog.availability(for: F.installed()).needsAttention)
        }
    }

    private func makeService(
        _ preferences: MemoryUpdatePreferences,
        client: UpdateModelClient,
    ) -> UpdateService {
        UpdateService(
            installed: F.installed(),
            preferences: preferences,
            client: client,
            now: { F.date },
        )
    }
}
