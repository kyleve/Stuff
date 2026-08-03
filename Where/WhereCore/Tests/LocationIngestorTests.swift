import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

/// Covers the GPS ingestion lifecycle, the post-persist hook, and the retry
/// queue the controller delegates all of `startGPS`/`stopGPS`/auth to.
struct LocationIngestorTests {
    private enum OutboxFailure: Error {
        case clear
    }

    private actor OutcomeRecorder {
        private(set) var outcomes: [LocationIngestor.IngestOutcome] = []

        func record(_ outcome: LocationIngestor.IngestOutcome) {
            outcomes.append(outcome)
        }

        var count: Int {
            outcomes.count
        }

        var last: LocationIngestor.IngestOutcome? {
            outcomes.last
        }
    }

    /// In-memory stand-in for the durable outbox: `load()` returns whatever was
    /// last `save`d, so two ingestors sharing one instance models the on-disk
    /// backlog surviving a relaunch.
    private actor SpyLocationOutbox: LocationOutbox {
        private(set) var entries: [LocationOutboxEntry]
        private let failsToClear: Bool

        init(_ contents: [LocationSample] = [], failsToClear: Bool = false) {
            entries = contents.map { LocationOutboxEntry(sample: $0, dataEpochID: .initial) }
            self.failsToClear = failsToClear
        }

        func load() async throws -> [LocationOutboxEntry] {
            entries
        }

        func save(_ entries: [LocationOutboxEntry]) async {
            self.entries = entries
        }

        func clear() async throws {
            if failsToClear { throw OutboxFailure.clear }
            entries = []
        }

        var contents: [LocationSample] {
            entries.map(\.sample)
        }
    }

    private static func makeIngestor(
        store: any WhereStore,
        source: ScriptedLocationSource,
        recorder: OutcomeRecorder,
        outbox: any LocationOutbox = NoOpLocationOutbox(),
        retryQueueCapacity: Int = 1000,
    ) -> LocationIngestor {
        LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
            calendar: WhereCoreTestSupport.calendar(),
            outbox: outbox,
            retryQueueCapacity: retryQueueCapacity,
            onPersisted: { outcome in await recorder.record(outcome) },
        )
    }

    @Test func startActivatesMonitoringAndStopPauses() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)

        try await ingestor.start()
        #expect(await ingestor.isActive)
        // The resume path fires a (drain-only) outcome even with an empty queue.
        #expect(await recorder.count == 1)
        #expect(await recorder.last?.liveSample == nil)

        await ingestor.stop()
        #expect(await !(ingestor.isActive))
    }

    @Test func currentLocationForwardsTheSourceFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        let fix = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-05-01T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.3349, longitude: -122.0090),
            horizontalAccuracy: 6,
            source: .gpsSignificantChange,
        )
        source.setNextRequestedLocation(fix)

        #expect(await ingestor.currentLocation() == fix)
    }

    @Test func currentLocationIsNilWhenSourceHasNoFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource()
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)

        #expect(await ingestor.currentLocation() == nil)
    }

    @Test func captureTodayPersistsAndReportsFixWhenNoGPSSampleYet() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        source.setNextRequestedLocation(sample(at: "2026-03-15T08:05:00-07:00"))
        try await ingestor.authorizeRecording()

        // No monitoring started (the When-In-Use case): the foreground fix is
        // the only way this user's data lands, and it still persists + reports.
        await ingestor
            .captureTodayIfNeeded(now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))

        // The post-persist outcome is reported *after* the write commits, so
        // wait on it directly rather than on the sample count — a count poll can
        // observe the committed row before `onPersisted` records the outcome.
        try await waitUntil { await recorder.last?.liveSample != nil }
        let stored = try await store.allSamples()
        #expect(stored.count == 1)
        #expect(stored.first?.recordingDeviceID == CurrentRecordingDevice.preview.id)
    }

    @Test func captureTodaySkipsWhenGPSSampleAlreadyExistsToday() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        // A passive GPS sample already covers today.
        try await store
            .perform { try await store.add(sample: sample(at: "2026-03-15T02:00:00-07:00")) }
        source.setNextRequestedLocation(sample(at: "2026-03-15T08:05:00-07:00"))
        try await ingestor.authorizeRecording()

        await ingestor
            .captureTodayIfNeeded(now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))

        // The day is already covered, so no fix is taken. Give the capture task
        // time to run and confirm it added nothing.
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await store.allSamples().count == 1)
    }

    @Test func captureTodayStillCapturesWhenOnlyManualSampleExistsToday() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        // A manual entry isn't a passive-tracking data point, so it must not
        // suppress the GPS fix.
        try await store.perform {
            try await store.add(sample: LocationSample(
                timestamp: WhereCoreTestSupport.iso("2026-03-15T02:00:00-07:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .manual,
            ))
        }
        source.setNextRequestedLocation(sample(at: "2026-03-15T08:05:00-07:00"))
        try await ingestor.authorizeRecording()

        await ingestor
            .captureTodayIfNeeded(now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))

        try await waitUntil { await (try? store.allSamples().count) == 2 }
    }

    @Test func captureTodaySkipsWhenSourceHasNoFix() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        // No fix scripted → `requestCurrentLocation()` returns nil.
        try await ingestor.authorizeRecording()

        await ingestor
            .captureTodayIfNeeded(now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"))

        try await Task.sleep(for: .milliseconds(100))
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func captureTodayIsSingleFlightWhileFixInFlight() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = GatedLocationSource(fix: sample(at: "2026-03-15T08:05:00-07:00"))
        let recorder = OutcomeRecorder()
        let ingestor = LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
            calendar: WhereCoreTestSupport.calendar(),
            onPersisted: { outcome in await recorder.record(outcome) },
        )
        let now = WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00")
        try await ingestor.authorizeRecording()

        // The first capture parks awaiting the gated fix, holding the
        // single-flight slot.
        await ingestor.captureTodayIfNeeded(now: now)
        try await waitUntil { source.requestCount == 1 }

        // A second call while the first is still in flight is dropped by the
        // single-flight guard — it never requests a fix of its own.
        await ingestor.captureTodayIfNeeded(now: now)

        // Release the fix: the first capture persists exactly one sample, and the
        // second never asked the source for one.
        source.openGate()
        try await waitUntil { await (try? store.allSamples().count) == 1 }
        #expect(source.requestCount == 1)
    }

    @Test func cancelledFixCannotReviveAfterRecordingIsReenabled() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = GatedLocationSource(fix: sample(at: "2026-03-15T08:05:00-07:00"))
        let ingestor = LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
            calendar: WhereCoreTestSupport.calendar(),
            onPersisted: { _ in },
        )
        try await ingestor.authorizeRecording()
        await ingestor.captureTodayIfNeeded(
            now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"),
        )
        try await waitUntil { source.requestCount == 1 }

        await ingestor.revokeRecordingAuthorization()
        try await ingestor.authorizeRecording()
        // The cancelled, continuation-backed request remains the single-flight owner until it
        // actually exits; re-enabling cannot replace it with a handle the old task could clear.
        await ingestor.captureTodayIfNeeded(
            now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"),
        )
        #expect(source.requestCount == 1)
        source.openGate()

        // Once the cancelled task exits, a genuinely new capture can claim the slot and persist.
        try await waitUntil {
            await ingestor.captureTodayIfNeeded(
                now: WhereCoreTestSupport.iso("2026-03-15T08:00:00-07:00"),
            )
            return source.requestCount == 2
        }
        try await waitUntil { await (try? store.allSamples().count) == 1 }
        #expect(source.requestCount == 2)
    }

    @Test func revokedAuthorizationDropsAOneShotFixEchoedOntoTheSampleStream() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = EchoingLocationSource(fix: sample(at: "2026-03-15T08:05:00-07:00"))
        let ingestor = LocationIngestor(
            store: store,
            locationSource: source,
            recordingDeviceID: CurrentRecordingDevice.preview.id,
            calendar: WhereCoreTestSupport.calendar(),
            onPersisted: { _ in },
        )
        try await ingestor.start()
        await ingestor.revokeRecordingAuthorization()

        #expect(await ingestor.currentLocation() != nil)
        try await waitUntil {
            guard source.didEchoFix else { return false }
            return await ingestor.testingHasConsumedSample(id: source.fixID)
        }

        #expect(try await store.allSamples().isEmpty)
    }

    @Test func sampleBufferedDuringInitialOffIsNotAcceptedByALaterOn() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
        )
        let beforeConsent = sample(at: "2026-03-15T11:59:00-07:00")
        let enabledAt = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let afterConsent = sample(at: "2026-03-15T12:01:00-07:00")

        // The source can buffer before the first policy reconciliation. Initial Off installs a
        // closed consumer; even if this row is not drained until after On, its timestamp remains
        // outside the new authority window.
        source.emit(beforeConsent)
        await ingestor.revokeRecordingAuthorization()
        try await ingestor.start(effectiveAt: enabledAt, dataEpochID: .initial)
        source.emit(afterConsent)

        try await waitUntil { await (try? store.allSamples().count) == 1 }
        #expect(try await store.allSamples().map(\.id) == [afterConsent.id])
    }

    @Test func liveSampleIsPersistedAndReported() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        try await ingestor.start()

        source.emit(LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ))

        try await waitUntil { await recorder.count >= 2 }
        #expect(await recorder.last?.liveSample != nil)
        #expect(try await store.allSamples().count == 1)
    }

    @Test func liveSampleFromSupersededEpochStopsWithoutEnteringRetryOutbox() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
        )
        try await ingestor.start(effectiveAt: .distantPast, dataEpochID: .initial)
        _ = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: CurrentRecordingDevice.preview.id,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }

        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))

        try await waitUntil { await !ingestor.testingIsAcceptingSamples }
        #expect(await !ingestor.isActive)
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func failedPersistEnqueuesThenLaterDrains() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        try await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // A later successful ingest drains the backlog before persisting itself.
        // Wait on the durable outcome (both samples committed) rather than
        // `retryQueueDepth == 0`: the drain clears the queue *before* it commits
        // the re-persists, so the depth hitting zero doesn't yet mean the data
        // has landed.
        await store.setShouldFail(false)
        source.emit(sample(at: "2026-03-15T13:00:00-07:00"))
        try await waitUntil { await (try? backing.allSamples().count) == 2 }
        #expect(await ingestor.retryQueueDepth == 0)
    }

    @Test func quiesceClearsTheRetryQueue() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        try await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // Quiescing for a teardown drops the backlog so a later start() can't
        // re-drain those samples into the freshly wiped store.
        try await ingestor.quiesce()
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await !(ingestor.isActive))
    }

    @Test func pausePreservesRetryBacklogForAResume() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }
        try await waitUntil { await outbox.contents.count == 1 }

        await ingestor.pause()

        #expect(await !(ingestor.isActive))
        #expect(await ingestor.retryQueueDepth == 1)
        #expect(await outbox.contents.count == 1)

        await store.setShouldFail(false)
        try await ingestor.start()

        try await waitUntil { await (try? backing.allSamples().count) == 1 }
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func quiesceStopsPersistingFurtherSamples() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        try await ingestor.start()

        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        // start() fires one drain-only outcome; the live sample fires a second.
        try await waitUntil { await recorder.count >= 2 }
        #expect(try await store.allSamples().count == 1)

        try await ingestor.quiesce()

        // A sample delivered after quiesce (e.g. a buffered event arriving mid
        // teardown) must not be persisted, so it can't clobber the wipe that
        // follows.
        source.emit(sample(at: "2026-03-15T13:00:00-07:00"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await store.allSamples().count == 1)
    }

    @Test func failedPersistMirrorsToTheDurableOutbox() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }

        // The failed sample is mirrored durably, not just held in memory — so it
        // can be recovered if the process dies before the next successful save.
        #expect(await outbox.contents.count == 1)
    }

    @Test func durableBacklogDrainsOnTheNextLaunch() async throws {
        let backing = try SwiftDataStore.inMemory()
        let failing = ToggleFailingStore(backing: backing)
        let outbox = SpyLocationOutbox()

        // First launch: the store is down, so the sample lands only in the
        // durable backlog (the app could now be killed).
        let source1 = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor1 = Self.makeIngestor(
            store: failing,
            source: source1,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor1.start()
        await failing.setShouldFail(true)
        source1.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor1.retryQueueDepth == 1 }
        #expect(await outbox.contents.count == 1)

        // Second launch: a brand-new ingestor over the *same* durable outbox and
        // a now-healthy store drains the backlog on start() — no data lost.
        let source2 = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor2 = Self.makeIngestor(
            store: backing,
            source: source2,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor2.start()

        try await waitUntil { await (try? backing.allSamples().count) == 1 }
        #expect(await ingestor2.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func durableBacklogPreservesExistingDeviceProvenance() async throws {
        let store = try SwiftDataStore.inMemory()
        let originalDeviceID = try RecordingDeviceID(
            rawValue: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")),
        )
        let restoredSample = LocationSample(
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
            recordingDeviceID: originalDeviceID,
        )
        let outbox = SpyLocationOutbox([restoredSample])
        let ingestor = Self.makeIngestor(
            store: store,
            source: ScriptedLocationSource(authorizationStatus: .always),
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )

        try await ingestor.start()

        let stored = try await store.allSamples()
        #expect(stored.count == 1)
        #expect(stored.first?.recordingDeviceID == originalDeviceID)
    }

    @Test func authorizingNewEpochDiscardsOldEpochBacklogWithoutPersistingIt() async throws {
        let store = try SwiftDataStore.inMemory()
        let newEpoch = try await store.perform {
            try await store.rotateDataEpoch(
                reason: .accountReset,
                changedBy: CurrentRecordingDevice.preview.id,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }
        let outbox = SpyLocationOutbox()
        await outbox.save([LocationOutboxEntry(
            sample: sample(at: "2026-03-15T12:00:00-07:00"),
            dataEpochID: .initial,
        )])
        let ingestor = Self.makeIngestor(
            store: store,
            source: ScriptedLocationSource(authorizationStatus: .always),
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )

        try await ingestor.authorizeRecording(
            effectiveAt: .distantPast,
            dataEpochID: newEpoch.id,
        )

        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await outbox.entries.isEmpty)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func epochRotationDuringBacklogDrainFailsClosedWithoutStartingGPS() async throws {
        let backing = try SwiftDataStore.inMemory()
        let gatedStore = ToggleFailingStore(backing: backing)
        let gate = OneShotGate()
        await gatedStore.gateNextExpectedEpochPerform(with: gate)
        let outbox = SpyLocationOutbox([sample(at: "2026-03-15T12:00:00-07:00")])
        let ingestor = Self.makeIngestor(
            store: gatedStore,
            source: ScriptedLocationSource(authorizationStatus: .always),
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )

        let start = Task {
            try await ingestor.start(effectiveAt: .distantPast, dataEpochID: .initial)
        }
        await gate.waitUntilEntered()
        _ = try await backing.perform {
            try await backing.rotateDataEpoch(
                reason: .accountReset,
                changedBy: CurrentRecordingDevice.preview.id,
                at: Date(timeIntervalSinceReferenceDate: 100),
            )
        }
        await gate.release()

        await #expect(throws: RecordingPersistenceError.dataEpochChanged) {
            try await start.value
        }
        #expect(await !ingestor.testingIsAcceptingSamples)
        #expect(await !ingestor.isActive)
        #expect(await ingestor.retryQueueDepth == 1)
        #expect(try await backing.allSamples().isEmpty)
    }

    @Test func quiesceClearsTheDurableOutbox() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor.start()

        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }
        #expect(await outbox.contents.count == 1)

        // A reset/erase teardown must wipe the durable backlog too, or it would
        // re-drain into the freshly erased store on the next launch.
        try await ingestor.quiesce()
        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func discardRetryBacklogClearsTheDurableAndLiveCopies() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox()
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor.start()
        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }
        try await waitUntil { await outbox.contents.count == 1 }
        await ingestor.pause()

        try await ingestor.discardRetryBacklog()

        #expect(await ingestor.retryQueueDepth == 0)
        #expect(await outbox.contents.isEmpty)
    }

    @Test func failedRetryBacklogDiscardPreservesTheLiveAndDurableCopies() async throws {
        let backing = try SwiftDataStore.inMemory()
        let store = ToggleFailingStore(backing: backing)
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let outbox = SpyLocationOutbox(failsToClear: true)
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            outbox: outbox,
        )
        try await ingestor.start()
        await store.setShouldFail(true)
        source.emit(sample(at: "2026-03-15T12:00:00-07:00"))
        try await waitUntil { await ingestor.retryQueueDepth == 1 }
        try await waitUntil { await outbox.contents.count == 1 }
        await ingestor.pause()

        await #expect(throws: OutboxFailure.self) {
            try await ingestor.discardRetryBacklog()
        }

        #expect(await ingestor.retryQueueDepth == 1)
        #expect(await outbox.contents.count == 1)
    }

    @Test func retryQueueEvictsOldestSampleAtCapacity() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .always)
        let ingestor = Self.makeIngestor(
            store: store,
            source: source,
            recorder: OutcomeRecorder(),
            retryQueueCapacity: 20,
        )
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let lastID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000001021"))

        for index in 1 ... 20 {
            let id = try #require(UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                index,
            )))
            await ingestor.testingEnqueueForRetry(LocationSample(
                id: id,
                timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
                coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
                horizontalAccuracy: 0,
                source: .gpsSignificantChange,
            ), dataEpochID: .initial)
        }
        #expect(await ingestor.retryQueueDepth == 20)

        await ingestor.testingEnqueueForRetry(LocationSample(
            id: lastID,
            timestamp: WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00"),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        ), dataEpochID: .initial)

        let queuedIDs = await ingestor.testingRetryQueueSampleIDs()
        #expect(queuedIDs.count == 20)
        #expect(!queuedIDs.contains(firstID))
        #expect(queuedIDs.contains(lastID))
    }

    @Test func authorizationReflectsTheSource() async throws {
        let store = try SwiftDataStore.inMemory()
        let source = ScriptedLocationSource(authorizationStatus: .whenInUse)
        let recorder = OutcomeRecorder()
        let ingestor = Self.makeIngestor(store: store, source: source, recorder: recorder)
        #expect(await ingestor.authorizationStatus() == .whenInUse)
    }

    private func sample(at isoString: String) -> LocationSample {
        LocationSample(
            timestamp: WhereCoreTestSupport.iso(isoString),
            coordinate: Coordinate(latitude: 37.7749, longitude: -122.4194),
            horizontalAccuracy: 0,
            source: .gpsSignificantChange,
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ predicate: () async -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !predicate() {
            if ContinuousClock.now >= deadline { throw WaitTimeout() }
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

private struct WaitTimeout: Error {}

/// `LocationSource` whose one-shot `requestCurrentLocation()` blocks until
/// `openGate()` is called, so a test can hold a capture "in flight" and prove
/// the single-flight guard drops an overlapping second request. Counts fix
/// requests so the test can assert the dropped call never reached the source.
private final class GatedLocationSource: LocationSource, @unchecked Sendable {
    let sampleStream: AsyncStream<LocationSample>
    var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { _ in }
    }

    private let fix: LocationSample
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var _requestCount = 0
    private var isOpen = false

    init(fix: LocationSample) {
        self.fix = fix
        sampleStream = AsyncStream { _ in }
    }

    var requestCount: Int {
        lock.withLock { _requestCount }
    }

    func start() async {}
    func stop() async {}
    func currentAuthorization() async -> LocationAuthorizationStatus {
        .whenInUse
    }

    func requestPermission() async throws {}

    func requestCurrentLocation() async -> LocationSample? {
        let shouldWait = lock.withLock {
            _requestCount += 1
            return !isOpen
        }
        guard shouldWait else { return fix }
        await withCheckedContinuation { continuation in
            let openedBeforeRegistration = lock.withLock {
                guard !isOpen else { return true }
                waiters.append(continuation)
                return false
            }
            if openedBeforeRegistration { continuation.resume() }
        }
        return fix
    }

    /// Resume every parked fix request with the scripted fix.
    func openGate() {
        let resumed = lock.withLock {
            isOpen = true
            let current = waiters
            waiters.removeAll()
            return current
        }
        for continuation in resumed {
            continuation.resume()
        }
    }
}

/// Models Core Location delivering a requested one-shot fix through both the direct callback and
/// the passive sample stream. The stream echo must still obey recording authority.
private final class EchoingLocationSource: LocationSource, @unchecked Sendable {
    let sampleStream: AsyncStream<LocationSample>
    var authorizationUpdates: AsyncStream<LocationAuthorizationStatus> {
        AsyncStream { _ in }
    }

    private let fix: LocationSample
    var fixID: UUID {
        fix.id
    }

    private let continuation: AsyncStream<LocationSample>.Continuation
    private let lock = NSLock()
    private var _didEchoFix = false

    init(fix: LocationSample) {
        self.fix = fix
        let stream = AsyncStream.makeStream(of: LocationSample.self)
        sampleStream = stream.stream
        continuation = stream.continuation
    }

    var didEchoFix: Bool {
        lock.withLock { _didEchoFix }
    }

    func start() async {}
    func stop() async {}
    func currentAuthorization() async -> LocationAuthorizationStatus {
        .always
    }

    func requestPermission() async throws {}

    func requestCurrentLocation() async -> LocationSample? {
        lock.withLock { _didEchoFix = true }
        continuation.yield(fix)
        return fix
    }
}

private struct ToggleFailingStoreError: Error {}

/// One-use suspension point whose entry can be awaited deterministically.
private actor OneShotGate {
    private var didEnter = false
    private var didRelease = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        didEnter = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard !didRelease else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !didEnter else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        didRelease = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

/// `WhereStore` that lets a test toggle whether `add(sample:)` succeeds; every
/// other API forwards to a real in-memory `SwiftDataStore`.
private actor ToggleFailingStore: WhereStore {
    private let backing: SwiftDataStore
    private var shouldFail = false
    private var nextExpectedEpochGate: OneShotGate?

    init(backing: SwiftDataStore) {
        self.backing = backing
    }

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func gateNextExpectedEpochPerform(with gate: OneShotGate) {
        nextExpectedEpochGate = gate
    }

    func perform<T: Sendable>(_ block: @Sendable () async throws -> T) async throws -> T {
        try await backing.perform(block)
    }

    func perform<T: Sendable>(
        expectedDataEpochID: WhereDataEpochID,
        _ block: @Sendable () async throws -> T,
    ) async throws -> T {
        if let gate = nextExpectedEpochGate {
            nextExpectedEpochGate = nil
            await gate.suspend()
        }
        return try await backing.perform(expectedDataEpochID: expectedDataEpochID, block)
    }

    nonisolated func changes() -> AsyncStream<Void> {
        backing.changes()
    }

    func dataEpoch() async throws -> WhereDataEpoch {
        try await backing.dataEpoch()
    }

    func rotateDataEpoch(
        reason: WhereDataEpochReason,
        changedBy deviceID: RecordingDeviceID,
        at date: Date,
    ) async throws -> WhereDataEpoch {
        try await backing.rotateDataEpoch(reason: reason, changedBy: deviceID, at: date)
    }

    func backupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws -> BackupImportReceipt? {
        try await backing.backupImportReceipt(id: id, installationID: installationID)
    }

    func addBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        try await backing.addBackupImportReceipt(id: id, installationID: installationID)
    }

    func removeBackupImportReceipt(
        id: UUID,
        installationID: RecordingDeviceID,
    ) async throws {
        try await backing.removeBackupImportReceipt(id: id, installationID: installationID)
    }

    func add(sample: LocationSample) async throws {
        if shouldFail { throw ToggleFailingStoreError() }
        try await backing.add(sample: sample)
    }

    func samples(in interval: DateInterval) async throws -> [LocationSample] {
        try await backing.samples(in: interval)
    }

    func allSamples() async throws -> [LocationSample] {
        try await backing.allSamples()
    }

    func recordingDevices() async throws -> [RecordingDevice] {
        try await backing.recordingDevices()
    }

    func recordingDeviceProfiles() async throws -> [RecordingDeviceProfile] {
        try await backing.recordingDeviceProfiles()
    }

    func addRecordingDeviceProfile(_ profile: RecordingDeviceProfile) async throws {
        try await backing.addRecordingDeviceProfile(profile)
    }

    func recordingDeviceMetadataChanges() async throws -> [RecordingDeviceMetadataChange] {
        try await backing.recordingDeviceMetadataChanges()
    }

    func addRecordingDeviceMetadataChange(_ change: RecordingDeviceMetadataChange) async throws {
        try await backing.addRecordingDeviceMetadataChange(change)
    }

    func recordingDeviceCheckIns() async throws -> [RecordingDeviceCheckIn] {
        try await backing.recordingDeviceCheckIns()
    }

    func setRecordingDeviceCheckIn(_ checkIn: RecordingDeviceCheckIn) async throws {
        try await backing.setRecordingDeviceCheckIn(checkIn)
    }

    func recordingPolicyChanges() async throws -> [RecordingPolicyChange] {
        try await backing.recordingPolicyChanges()
    }

    func addRecordingPolicyChange(_ change: RecordingPolicyChange) async throws {
        try await backing.addRecordingPolicyChange(change)
    }

    func recordingAssignmentChanges() async throws -> [RecordingAssignmentChange] {
        try await backing.recordingAssignmentChanges()
    }

    func addRecordingAssignmentChange(_ change: RecordingAssignmentChange) async throws {
        try await backing.addRecordingAssignmentChange(change)
    }

    func recordingDeviceArchives() async throws -> [RecordingDeviceArchive] {
        try await backing.recordingDeviceArchives()
    }

    func addRecordingDeviceArchive(_ archive: RecordingDeviceArchive) async throws {
        try await backing.addRecordingDeviceArchive(archive)
    }

    func write(evidence: Evidence, blob: Data?) async throws {
        try await backing.write(evidence: evidence, blob: blob)
    }

    func evidence(in interval: DateInterval) async throws -> [Evidence] {
        try await backing.evidence(in: interval)
    }

    func allEvidence() async throws -> [Evidence] {
        try await backing.allEvidence()
    }

    func evidenceBlob(for id: UUID) async throws -> Data? {
        try await backing.evidenceBlob(for: id)
    }

    func setManualDay(_ day: DayPresence) async throws {
        try await backing.setManualDay(day)
    }

    func clearManualDay(_ day: CalendarDay) async throws {
        try await backing.clearManualDay(day)
    }

    func manualDays(in dayRange: ClosedRange<CalendarDay>) async throws -> [DayPresence] {
        try await backing.manualDays(in: dayRange)
    }

    func allManualDays() async throws -> [DayPresence] {
        try await backing.allManualDays()
    }

    func clear(
        in interval: DateInterval,
        manualDays dayRange: ClosedRange<CalendarDay>,
    ) async throws {
        try await backing.clear(in: interval, manualDays: dayRange)
    }

    func dismissedIssueIDs() async throws -> Set<DataIssueID> {
        try await backing.dismissedIssueIDs()
    }

    func allDismissedIssues() async throws -> [DismissedIssue] {
        try await backing.allDismissedIssues()
    }

    func setIssueDismissed(_ dismissed: Bool, id: DataIssueID) async throws {
        try await backing.setIssueDismissed(dismissed, id: id)
    }

    func restoreDismissedIssue(_ issue: DismissedIssue) async throws {
        try await backing.restoreDismissedIssue(issue)
    }
}
