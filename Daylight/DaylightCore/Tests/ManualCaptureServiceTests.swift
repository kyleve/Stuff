@testable import DaylightCore
import Foundation
import Testing

struct ManualCaptureServiceTests {
    @Test func shotSavesToPhotosWithoutPublishingAndPersistsArmingIntent() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.manualCapture()
        try await engine.publishPending()
        #expect(await fixture.publisher.count == 0)
        let record = try #require(try await engine.manualHistory().first)
        if case let .captured(image) = record.state { #expect(image.photos == .saved("saved")) }
        else { Issue.record("Test shot was not saved") }
        #expect(try await engine.armedIntent() == false)
        try await engine.setArmedIntent(true)
        let reopened = try CaptureStore(root: fixture.root)
        #expect(try await reopened.armedIntent())
        try await engine.setArmedIntent(false)
        #expect(try await reopened.armedIntent() == false)
    }

    @Test func legacySavedShotRecoversWithoutRecaptureOrAnotherPhotosSave() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let data = Data(
            #"{"version":1,"value":{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"date":1000,"state":{"captured":{"_0":{"id":{"rawValue":"00000000-0000-0000-0000-000000000001"},"capturedAt":1000,"photos":{"saved":{"_0":"existing-asset"}},"score":{"pending":{}},"recipe":{"preset":"original"}}}}}}"#
                .utf8,
        )
        let url = fixture.root.appendingPathComponent("manual-legacy.json")
        try data.write(to: url)
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.tick(canCapture: false)
        let record = try #require(try await engine.manualHistory().first)
        guard case let .captured(image) = record.state else {
            Issue.record("Saved legacy capture was lost"); return
        }
        #expect(image.photos == .saved("existing-asset"))
        #expect(await fixture.camera.count == 0)
        #expect(await fixture.publisher.count == 0)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func disarmedRecoveryFinishesStagedTestShotWithoutUsingCamera() async throws {
        let fixture = try CaptureHarness()
        defer { do { try fixture.clean() } catch { Issue.record(error) } }
        let record = ManualCapture(date: fixture.clock.now)
        try await fixture.store.saveManual(record)
        try await fixture.store.stage(
            Data("original".utf8),
            imageID: record.id,
            resource: .original,
        )
        let engine = fixture.engine(photos: ScriptedPhotos(), scorer: ScriptedScorer())
        _ = try await engine.load()
        try await engine.tick(canCapture: false)
        #expect(await fixture.camera.count == 0)
        #expect(await fixture.publisher.count == 0)
        let recovered = try #require(try await engine.manualHistory().first)
        if case let .captured(image) = recovered.state { #expect(image.photos == .saved("saved")) }
        else { Issue.record("Test shot did not recover") }
    }
}
