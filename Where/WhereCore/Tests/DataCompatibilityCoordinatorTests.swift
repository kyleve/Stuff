import CloudKit
import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

@MainActor
struct DataCompatibilityCoordinatorTests {
    @Test func obsoleteOfflineHeaderCompletionCannotRevokeANewerVerifiedScope() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await coordinator.refresh()
        let verificationGate = CompatibilityTestGate()
        let headerGate = CompatibilityTestGate()
        await transport.holdNextVerification(verificationGate)
        await transport.failVerification(CKError(.networkUnavailable))
        let older = Task { try await coordinator.refresh() }
        await verificationGate.waitUntilEntered()
        await store.afterNextCompatibilityRead { await headerGate.suspend() }
        await verificationGate.resume()
        await headerGate.waitUntilEntered()
        await transport.failVerification(nil)
        let current = try await coordinator.refresh()
        await headerGate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) { try await older.value }
        try current.validate()
        #expect(coordinator.access?.id == current.id)
        #expect(try cache.load()?.verified == true)
    }

    @Test(arguments: [false, true])
    func sharedInitializationPrecedesMirrorCreation(hasExistingHistory: Bool) async throws {
        let database = ScriptedDataCompatibilityControlDatabase(legacyZone: false)
        let transport = CloudKitDataCompatibilityTransport(database: database)
        let store = try SwiftDataStore.inMemory()
        let factory = ScriptedCompatibilityStoreFactory(store: store, gate: nil)
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: DataCompatibilityStorePreparation(
                hasExistingHistory: hasExistingHistory,
                makeStore: {
                    await database.createMirrorZone()
                    return try await factory.open()
                },
            ),
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: InMemoryDataCompatibilityCache(value: nil),
            ),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        coordinator.startObserving()
        let access = try await coordinator.refresh()
        #expect(access.requiredMajor == (hasExistingHistory ? 0 : 1))
        #expect(await database.committedSaves == 1)
        #expect(await factory.openings == 1)
        #expect(try await coordinator.refresh().id == access.id)
        #expect(await factory.openings == 1)
    }

    @Test func failedSharedPreflightDoesNotOpenAStoreOrCreateAMirror() async throws {
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        await transport.failVerification(CKError(.networkUnavailable))
        let factory = try ScriptedCompatibilityStoreFactory(
            store: SwiftDataStore.inMemory(),
            gate: nil,
        )
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: .init(hasExistingHistory: false, makeStore: {
                try await factory.open()
            }),
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: InMemoryDataCompatibilityCache(value: nil),
            ),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        await #expect(throws: CKError.self) { try await coordinator.refresh() }
        #expect(await factory.openings == 0)
        #expect(await transport.creations == 0)
    }

    @Test func openedHeadersAreAdmittedBeforeSavingACompatibleGrant() async throws {
        let store = try SwiftDataStore.inMemory()
        try await store.perform { try await store.raiseRequiredDataMajor(2) }
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: .init(hasExistingHistory: true, makeStore: { store }),
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: cache,
            ),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try await coordinator.refresh()
        }
        #expect(coordinator.access == nil)
        #expect(try cache.load()?.requiredMajor == 2)
        #expect(try cache.load()?.verified == false)
    }

    @Test func accountInvalidationDuringOpeningCannotGrantAccess() async throws {
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let gate = CompatibilityTestGate()
        let factory = try ScriptedCompatibilityStoreFactory(
            store: SwiftDataStore.inMemory(),
            gate: gate,
        )
        let coordinator = DataCompatibilityCoordinator(
            storePreparation: .init(hasExistingHistory: false, makeStore: {
                try await factory.open()
            }),
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: cache,
            ),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        let opening = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        coordinator.invalidateAccount()
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await opening.value
        }
        #expect(coordinator.access == nil)
        #expect(try cache.load()?.verified == false)
        #expect(await factory.openings == 1)
    }

    @Test func completedOverlappingReadsRestoreColdOfflineAccess() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await coordinator.refresh()
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let older = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        let current = try await coordinator.refresh()
        #expect(try cache.load()?.verified == false)
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) { try await older.value }
        #expect(try cache.load()?.verified == true)
        try current.validate()
        let relaunched = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await transport.failVerification(CKError(.networkUnavailable))
        #expect(try await relaunched.refresh().requiredMajor == 0)
    }

    @Test(arguments: [false, true])
    func failedHigherRequirementWriteCannotRestoreAnOlderGrantAfterRelaunch(
        overlappingRefresh: Bool,
    ) async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = ScriptedDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await coordinator.refresh()
        await transport.establish(major: 2)
        cache.rejectedMajor = 2
        if overlappingRefresh {
            let gate = CompatibilityTestGate()
            await transport.holdNextVerification(gate)
            let higher = Task { try await coordinator.refresh() }
            await gate.waitUntilEntered()
            await transport.establish(major: 0)
            _ = try await coordinator.refresh()
            #expect(try cache.load()?.verified == false)
            await gate.resume()
            await #expect(throws: ScriptedDataCompatibilityCache.WriteFailure.self) {
                try await higher.value
            }
        } else {
            await #expect(throws: ScriptedDataCompatibilityCache.WriteFailure.self) {
                try await coordinator.refresh()
            }
        }
        #expect(coordinator.knownRequiredMajor == 2)
        #expect(coordinator.access == nil)
        #expect(try cache.load()?.verified == false)
        let relaunched = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await transport.failVerification(CKError(.networkUnavailable))
        await #expect(throws: CKError.self) { try await relaunched.refresh() }
        #expect(relaunched.access == nil)
    }

    @Test func interruptedVerificationRequiresACompletedCheckAfterRelaunch() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let original = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await original.refresh()
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let interrupted = Task { try await original.refresh() }
        await gate.waitUntilEntered()
        #expect(try cache.load()?.verified == false)
        let relaunched = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await transport.failVerification(CKError(.networkUnavailable))
        await #expect(throws: CKError.self) { try await relaunched.refresh() }
        #expect(relaunched.access == nil)
        interrupted.cancel()
        await transport.failVerification(nil)
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await interrupted.value }
        #expect(try await relaunched.refresh().requiredMajor == 0)
    }

    @Test func emptyLocalDatasetDoesNotRequireSupportForLegacyMajorZero() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: DataCompatibilityTestSupport.storeID),
            policy: .init(current: .init(major: 1, minor: 0, patch: 0), supportedMajors: [1]),
            activationReadiness: .ready,
        )
        #expect(try await coordinator.refresh().requiredMajor == 1)
    }

    @Test func emptySharedDatasetDoesNotInventALegacyRequirement() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: InMemoryDataCompatibilityCache(value: nil),
            ),
            policy: .init(current: .init(major: 1, minor: 0, patch: 0), supportedMajors: [1]),
            activationReadiness: .ready,
        )
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let opening = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        if case .unknown = coordinator.state {} else { Issue.record("Newness is still unknown") }
        await gate.resume()
        let access = try await opening.value
        #expect(access.requiredMajor == 1)
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        try await access.store.perform { try await access.store.restoreHomeRegionRecord(home) }
        #expect(try await coordinator.refresh().store.homeRegionRecords().count == 1)
    }

    @Test func localDatasetInitializesAndUpgradesWithoutAnAccount() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .local(storeID: DataCompatibilityTestSupport.storeID),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        let access = try await coordinator.refresh()
        #expect(access.requiredMajor == 1)
        try access.validate()
    }

    @Test func legacySharedAccountIsNotInitializedAsNewFromLocalEmptiness() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        #expect(try await coordinator.refresh().requiredMajor == 0)
        #expect(await transport.creations == 1)
        #expect(await transport.advances == 0)
    }

    @Test func sameAccountRefreshFailureKeepsOfflineAccessWithoutAClockExpiry() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let first = try await coordinator.refresh()
        await transport.failVerification(CKError(.networkUnavailable))
        let cached = try await coordinator.refresh()
        #expect(cached.id == first.id)
        if case .available(_, .uncertain) = coordinator.state {}
        else { Issue.record("Expected sync uncertainty") }
        try cached.validate()
    }

    @Test func coldCacheRequiresCurrentAccountIdentity() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        await transport.failIdentity(CKError(.networkUnavailable))
        let cache = InMemoryDataCompatibilityCache(value: .init(
            storeID: DataCompatibilityTestSupport.storeID,
            accountID: ScriptedSharedDataCompatibilityTransport.account,
            requiredMajor: 1,
            verified: true,
        ))
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await #expect(throws: CKError.self) { try await coordinator.refresh() }
        #expect(coordinator.access == nil)
        #expect(await transport.creations == 0)
    }

    @Test func lateVerificationCannotRestoreAnInvalidatedAccount() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let refresh = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        coordinator.invalidateAccount()
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await refresh.value
        }
        #expect(coordinator.access == nil)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
    }

    @Test func staleLowerVerificationCannotUndoAKnownHigherRequirement() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport =
            ScriptedSharedDataCompatibilityTransport(history: .existing(DataCompatibilityTestSupport
                    .state(major: 0)))
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let stale = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        await transport.establish(major: 2)
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try await coordinator.refresh()
        }
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) { try await stale.value }
        #expect(coordinator.knownRequiredMajor == 2)
        #expect(coordinator.access == nil)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
    }

    @Test func explicitUpgradeAdvancesAfterVerificationAndReplacesTheScope() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        let new = try await coordinator.activateCurrentMajor(
            authorization: .confirmedByUser,
            now: Date(),
        )
        #expect(new.requiredMajor == 1)
        #expect(new.id != old.id)
        #expect(await transport.advances == 1)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
    }

    @Test func supersededHigherResponseRemainsKnownAfterRelaunch() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await coordinator.refresh()
        await transport.establish(major: 2)
        let gate = CompatibilityTestGate()
        await transport.holdNextVerification(gate)
        let stale = Task { try await coordinator.refresh() }
        await gate.waitUntilEntered()
        // The newer response can be a stale server/cache result. Arrival order is not authority.
        await transport.establish(major: 0)
        _ = try await coordinator.refresh()
        await gate.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) { try await stale.value }
        #expect(try cache.load()?.requiredMajor == 2)
        let relaunched = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await #expect(throws: DataCompatibilityError.updateRequired(requiredMajor: 2)) {
            try await relaunched.refresh()
        }
        #expect(relaunched.access == nil)
    }

    @Test func supportedImportReplacesTheOldMajorScope() async throws {
        let source = ScriptedStoreRemoteChangeSource()
        let store = try SwiftDataStore.inMemory(remoteChangeSource: source)
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        coordinator.startObserving()
        await transport.establish(major: 1)
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        source.yield()
        try await DataCompatibilityTestSupport.waitUntil { coordinator.access?.requiredMajor == 1 }
        #expect(coordinator.access?.id != old.id)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
    }

    @Test func authenticationFailureInvalidatesCachedOfflineAdmission() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .newAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        let old = try await coordinator.refresh()
        await transport.failIdentity(CKError(.notAuthenticated))
        await #expect(throws: CKError.self) { try await coordinator.refresh() }
        await transport.failIdentity(CKError(.networkUnavailable))
        await #expect(throws: CKError.self) { try await coordinator.refresh() }
        #expect(try cache.load()?.verified == false)
        #expect(coordinator.access == nil)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
    }

    @Test func lostUpgradeResponseCannotRestoreAnOlderCachedGrant() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        let old = try await coordinator.refresh()
        await transport.loseAdvanceResponse(CKError(.networkFailure))
        await #expect(throws: CKError.self) {
            try await coordinator.activateCurrentMajor(authorization: .confirmedByUser, now: Date())
        }
        await transport.failVerification(CKError(.networkUnavailable))
        await #expect(throws: CKError.self) { try await coordinator.refresh() }
        #expect(coordinator.access == nil)
        #expect(try cache.load()?.verified == false)
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
        await transport.failVerification(nil)
        #expect(try await coordinator.refresh().requiredMajor == 1)
    }

    @Test func activationOnANewCoordinatorInvalidatesItsDurableCache() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: nil)
        let initial = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        _ = try await initial.refresh()
        let relaunched = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        await transport.loseAdvanceResponse(CKError(.networkFailure))
        await #expect(throws: CKError.self) {
            try await relaunched.activateCurrentMajor(authorization: .confirmedByUser, now: Date())
        }
        #expect(try cache.load()?.verified == false)
        await transport.failVerification(CKError(.networkUnavailable))
        await #expect(throws: CKError.self) { try await relaunched.refresh() }
        #expect(relaunched.access == nil)
    }

    @Test func refreshCannotGrantAccessWhileAnUpgradeIsInFlight() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        let gate = CompatibilityTestGate()
        await transport.holdAdvance(gate)
        await transport.loseAdvanceResponse(CKError(.networkFailure))
        let upgrade = Task { try await coordinator.activateCurrentMajor(
            authorization: .confirmedByUser,
            now: Date(),
        ) }
        await gate.waitUntilEntered()
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await coordinator.refresh()
        }
        #expect(coordinator.access == nil)
        await gate.resume()
        await #expect(throws: CKError.self) { try await upgrade.value }
        #expect(throws: DataAccessPermit.AccessError.revoked) { try old.validate() }
        #expect(try await coordinator.refresh().requiredMajor == 1)
    }

    @Test func cacheForAnotherStoreCannotRaiseThisDatasetsRequirement() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = InMemoryDataCompatibilityCache(value: .init(
            storeID: .init(rawValue: "different-store"),
            accountID: ScriptedSharedDataCompatibilityTransport.account,
            requiredMajor: 99,
            verified: true,
        ))
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: cache,
        )
        #expect(try await coordinator.refresh().requiredMajor == 0)
        #expect(try cache.load()?.storeID == DataCompatibilityTestSupport.storeID)
        #expect(try cache.load()?.requiredMajor == 0)
    }

    @Test func failedDurableInvalidationPreventsAnyServerMutation() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let cache = FailingDataCompatibilityCache(value: .init(
            storeID: DataCompatibilityTestSupport.storeID,
            accountID: ScriptedSharedDataCompatibilityTransport.account,
            requiredMajor: 0,
            verified: true,
        ))
        let coordinator = DataCompatibilityCoordinator(
            store: store,
            source: .cloudKit(
                storeID: DataCompatibilityTestSupport.storeID,
                transport: transport,
                cache: cache,
            ),
            policy: DataCompatibilityTestSupport.policy,
            activationReadiness: .ready,
        )
        await #expect(throws: FailingDataCompatibilityCache.WriteFailure.self) {
            try await coordinator.activateCurrentMajor(authorization: .confirmedByUser, now: Date())
        }
        #expect(await transport.creations == 0)
        #expect(await transport.advances == 0)
        #expect(coordinator.access == nil)
    }

    @Test func obsoleteActivationCannotClearAnotherActivationsFence() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        _ = try await coordinator.refresh()
        let firstSave = CompatibilityTestGate()
        await transport.holdAdvance(firstSave)
        let first = Task { try await coordinator.activateCurrentMajor(
            authorization: .confirmedByUser,
            now: Date(),
        ) }
        await firstSave.waitUntilEntered()
        let firstFinalRefresh = CompatibilityTestGate()
        await transport.holdNextVerification(firstFinalRefresh)
        await firstSave.resume()
        await firstFinalRefresh.waitUntilEntered()
        let secondSave = CompatibilityTestGate()
        await transport.holdAdvance(secondSave)
        let second = Task { try await coordinator.activateCurrentMajor(
            authorization: .confirmedByUser,
            now: Date(),
        ) }
        await secondSave.waitUntilEntered()
        await firstFinalRefresh.resume()
        await #expect(throws: DataCompatibilityError.verificationRequired) { try await first.value }
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await coordinator.refresh()
        }
        await secondSave.resume()
        #expect(try await second.value.requiredMajor == 1)
    }

    @Test func obsoleteImportRefreshCannotRevokeANewerGrant() async throws {
        let store = try SwiftDataStore.inMemory()
        let transport = ScriptedSharedDataCompatibilityTransport(history: .legacyAccount)
        let coordinator = DataCompatibilityTestSupport.coordinator(
            store: store,
            transport: transport,
            cache: InMemoryDataCompatibilityCache(value: nil),
        )
        let old = try await coordinator.refresh()
        try await store.perform { try await store.raiseRequiredDataMajor(1) }
        await transport.establish(major: 1)
        let staleVerification = CompatibilityTestGate()
        await transport.holdNextVerification(staleVerification)
        await #expect(throws: DataCompatibilityError.verificationRequired) {
            try await old.store.allSamples()
        }
        await staleVerification.waitUntilEntered()
        let current = try await coordinator.refresh()
        await staleVerification.resume()
        await coordinator.waitForImportRecovery()
        let after = try await coordinator.refresh()
        #expect(after.id == current.id)
        try current.validate()
    }
}
