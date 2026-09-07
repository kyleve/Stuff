@_spi(Testing) @testable import DaylightCore
import Foundation
import PeriscopeCore
import Testing

struct CaptureEngineTests {
    @Test func capturesOnceSkipsMissedSlotsAndPublishesOneHighlight() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: folder) } catch { Issue.record(error) }
        }
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunrise),
            date: Date(timeIntervalSince1970: 1_782_046_800),
        )
        let clock = CaptureTestClock(event.date.addingTimeInterval(-1800))
        let camera = ScriptedCamera(); let photos = ScriptedPhotos(); let publisher =
            ScriptedPublisher()
        let store = try CaptureStore(root: folder)
        let logging = Periscope(configuration: .init(), sinks: [])
        let engine = CaptureEngine(
            store: store,
            camera: camera,
            solar: ScriptedSolar(event: event),
            photos: photos,
            scorer: ScriptedScorer(),
            destinations: [publisher],
            log: Log<DaylightLogEvent>(system: logging),
            now: { clock.now },
        )
        _ = try await engine.load()
        try await engine.tick(canCapture: true)
        try await engine.tick(canCapture: true)
        #expect(await camera.count == 1)
        #expect(await photos.count == 1)
        var settings = CaptureSettings.standard
        settings.camera.zoom = 2
        try await engine.configure(settings)
        clock.advance(3631)
        try await engine.tick(canCapture: true)
        let sequence = try #require(await engine.history().first)
        #expect(sequence.images.count == 1)
        #expect(sequence.settings.camera.zoom == 1)
        #expect(sequence.slots
            .count(where: { if case .missed = $0.state { true } else { false } }) == 12)
        try await engine.publishPending()
        try await engine.publishPending()
        #expect(await publisher.count == 1)
        let persisted = try #require(try await store.sequences().first)
        #expect(persisted.deliveries.count == 1)
        if case .delivered = persisted.deliveries[0].state {}
        else { Issue.record("Delivery did not finish") }
    }

    @Test func reconcilesRecordedPhotosIdentifierWithoutAnotherSave() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: folder) } catch { Issue.record(error) }
        }
        let event = SolarEvent(
            id: .init(year: 2026, month: 6, day: 21, kind: .sunset),
            date: Date(timeIntervalSince1970: 1_782_046_800),
        )
        let clock = CaptureTestClock(event.date.addingTimeInterval(-1790))
        var sequence = CaptureSequence(event: event, settings: .standard)
        let slot = sequence.slots[0]
        var image = CapturedImage(id: slot.id, capturedAt: slot.scheduledAt, format: .jpeg)
        image.photos = .saving("saved")
        sequence.slots[0].state = .captured(image)
        let store = try CaptureStore(root: folder)
        try await store.stage(Data("image".utf8), imageID: slot.id, resource: .original)
        try await store.save(sequence)
        let photos = ScriptedPhotos()
        let engine = CaptureEngine(
            store: store,
            camera: ScriptedCamera(),
            solar: ScriptedSolar(event: event),
            photos: photos,
            scorer: ScriptedScorer(),
            destinations: [],
            log: Log<DaylightLogEvent>(system: Periscope(configuration: .init(), sinks: [])),
            now: { clock.now },
        )
        _ = try await engine.load()
        try await engine.tick(canCapture: true)
        #expect(await photos.count == 0)
        let recovered = try #require(await engine.history().first?.images.first)
        #expect(recovered.photos == .saved("saved"))
    }

    @Test func fullSequenceSurvivesClockReversalWithoutDuplicates() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        for _ in 0 ..< 13 {
            try await engine.tick(canCapture: true)
            fixture.clock.advance(-60)
            try await engine.tick(canCapture: true)
            fixture.clock.advance(360)
        }
        try await engine.tick(canCapture: true)
        try await engine.publishPending()
        #expect(await fixture.camera.count == 13)
        #expect(await fixture.publisher.count == 1)
    }

    @Test func diskExhaustionPausesBeforeCameraAndRetainsFutureSlots() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        await fixture.store.overrideAvailableCapacity(0)
        await #expect(throws: DaylightError.self) { try await engine.tick(canCapture: true) }
        #expect(await fixture.camera.count == 0)
        await fixture.store.overrideAvailableCapacity(1_000_000_000)
        fixture.clock.advance(300)
        try await engine.tick(canCapture: true)
        #expect(await fixture.camera.count == 1)
        #expect(await engine.history().first?.slots.first?.state == .missed)
    }

    @Test func photosFailureDoesNotBlockSelectionOrPublishing() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let engine = fixture.engine(photos: FailingPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.tick(canCapture: true)
        fixture.clock.advance(3631)
        try await engine.tick(canCapture: true)
        try await engine.publishPending()
        let image = try #require(await engine.history().first?.images.first)
        if case .retry = image.photos {} else { Issue.record("Expected retryable Photos failure") }
        #expect(await fixture.publisher.count == 1)
        let original = await fixture.store.imageURL(image.id, resource: .original)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func scoringFailureRetainsImagesAndNeverPublishes() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: FailingScorer())
        _ = try await engine.load()
        try await engine.tick(canCapture: true)
        fixture.clock.advance(3631)
        try await engine.tick(canCapture: true)
        try await engine.publishPending()
        let sequence = try #require(await engine.history().first)
        if case .failed = sequence.selection {} else { Issue.record("Expected failed selection") }
        #expect(await fixture.publisher.count == 0)
        let image = try #require(sequence.images.first)
        let original = await fixture.store.imageURL(image.id, resource: .original)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func interruptedSlotIsRecoveredWithoutAnotherCapture() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        var sequence = CaptureSequence(event: fixture.event, settings: .standard)
        sequence.slots[0].state = .capturing
        try await fixture.store.stage(
            Data("original".utf8),
            imageID: sequence.slots[0].id,
            resource: .original,
        )
        try await fixture.store.save(sequence)
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.tick(canCapture: true)
        #expect(await fixture.camera.count == 0)
        #expect(await engine.history().first?.images.count == 1)
    }
}

extension CaptureEngineTests {
    @Test(.timeLimit(.minutes(1))) func cleanupWaitsForHighlightRegistration() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        var sequence = CaptureSequence(event: fixture.event, settings: .standard)
        for index in sequence.slots.indices {
            sequence.slots[index].state = .missed
        }
        let slot = sequence.slots[0]
        var image = CapturedImage(id: slot.id, capturedAt: slot.scheduledAt, format: .jpeg)
        image.photos = .saved("saved"); image.score = .scored(.init(
            overall: 0.8,
            isUtility: false,
        )); image.capturedEventHandled = true
        sequence.slots[0].state = .captured(image)
        try await fixture.store.save(sequence)
        try await fixture.store.stage(Data("original".utf8), imageID: image.id, resource: .original)
        fixture.clock.advance(3631)
        let destination = GatedPublisher()
        let engine = CaptureEngine(
            store: fixture.store,
            camera: fixture.camera,
            solar: ScriptedSolar(event: fixture.event),
            photos: ScriptedPhotos(),
            scorer: ScriptedScorer(),
            destinations: [destination],
            log: Log<DaylightLogEvent>(system: Periscope(configuration: .init(), sinks: [])),
            now: { fixture.clock.now },
        )
        _ = try await engine.load()
        let tick = Task { try await engine.tick(canCapture: false) }
        await destination.waitUntilEntered()
        try await engine.publishPending()
        let url = await fixture.store.imageURL(image.id, resource: .original)
        #expect(FileManager.default.fileExists(atPath: url.path))
        await destination.release()
        try await tick.value
        #expect(await engine.history().first?.deliveries.count == 1)
        #expect(try await fixture.store.sequences().first?.deliveries.count == 1)
    }
}

extension CaptureEngineTests {
    @Test func permissionRestorationRetriesPhotosAfterBackoffAcrossRelaunch() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let first = fixture.engine(photos: FailingPhotos(), scorer: ScriptedScorer())
        _ = try await first.load()
        try await first.tick(canCapture: true)
        let photos = ScriptedPhotos()
        let reopened = fixture.engine(photos: photos, scorer: ScriptedScorer())
        _ = try await reopened.load()
        try await reopened.tick(canCapture: false)
        #expect(await photos.count == 0)
        fixture.clock.advance(31)
        try await reopened.tick(canCapture: false)
        #expect(await photos.count == 1)
        #expect(await reopened.history().first?.images.first?.photos == .saved("saved"))
        #expect(await fixture.camera.count == 1)
    }

    @Test func ambiguousPhotoRequiresConfirmationAndChecksExistingReceipt() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        var sequence = CaptureSequence(event: fixture.event, settings: .standard)
        let slot = sequence.slots[0]
        var image = CapturedImage(id: slot.id, capturedAt: slot.scheduledAt, format: .jpeg)
        image.photos = .ambiguous
        sequence.slots[0].state = .captured(image)
        try await fixture.store.save(sequence)
        try await fixture.store.stage(Data("image".utf8), imageID: slot.id, resource: .original)
        let photos = ScriptedPhotos()
        let engine = fixture.engine(photos: photos, scorer: ScriptedScorer())
        _ = try await engine.load()
        await #expect(throws: DaylightError.self) { try await engine.resolvePhotos(
            imageID: image.id,
            resolution: .retry,
        ) }
        let original = await fixture.store.imageURL(slot.id, resource: .original)
        try Data("saved".utf8)
            .write(to: original.deletingPathExtension().appendingPathExtension("photos-receipt"))
        try await engine.resolvePhotos(imageID: image.id, resolution: .confirmedAbsent)
        #expect(await engine.history().first?.images.first?.photos == .saved("saved"))
        #expect(await photos.count == 0)
    }

    @Test func deliveryRecoveryPreservesIdentityAndPriorCheckpoints() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        var sequence = CaptureSequence(event: fixture.event, settings: .standard)
        var delivery = PublishingDelivery(
            destination: fixture.publisher.id,
            imageID: sequence.slots[0].id,
            kind: .sequenceHighlight,
        )
        delivery.checkpoint = Data("earlier submission".utf8)
        delivery.state = .needsAttention("Check the previous post")
        delivery.attempts = 3
        sequence.deliveries = [delivery]
        try await fixture.store.save(sequence)
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.recoverDelivery(
            sequenceID: sequence.id,
            deliveryID: delivery.id,
            action: .confirmedAbsent,
        )
        let recovered = try #require(try await fixture.store.sequences().first?.deliveries.first)
        #expect(recovered.id == delivery.id)
        #expect(recovered.attempts == 3)
        #expect(recovered.checkpoint == nil)
        #expect(recovered.recoveryHistory == [Data("earlier submission".utf8)])
        if case .pending = recovered.state {} else { Issue.record("Delivery was not requeued") }
    }

    @Test func recordedPostReceiptPreventsAnotherDelivery() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        var sequence = CaptureSequence(event: fixture.event, settings: .standard)
        var delivery = PublishingDelivery(
            destination: fixture.publisher.id,
            imageID: sequence.slots[0].id,
            kind: .sequenceHighlight,
        )
        delivery.state = .needsAttention("Check the previous post")
        sequence.deliveries = [delivery]
        try await fixture.store.save(sequence)
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        let url = try #require(URL(string: "https://example.com/@camera/123"))
        try await engine.recoverDelivery(
            sequenceID: sequence.id,
            deliveryID: delivery.id,
            action: .published(url),
        )
        try await engine.publishPending()
        let recovered = try #require(try await fixture.store.sequences().first?.deliveries.first)
        if case let .delivered(receipt) = recovered.state { #expect(receipt.url == url) }
        else { Issue.record("Post receipt was not recorded") }
        #expect(await fixture.publisher.count == 0)
    }
}
