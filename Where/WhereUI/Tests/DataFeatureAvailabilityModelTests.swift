import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct DataFeatureAvailabilityModelTests {
    @Test func observesReadinessWithoutActivatingOrPublishingCapabilities() async throws {
        let world = try await DataFeatureAvailabilityTestSupport.makeWorld()
        let model = DataFeatureAvailabilityModel(
            requiring: DataFeatureAvailabilityTestSupport.version,
            source: world.services.compatibility,
        )
        #expect(model.state == .checking)
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .needsDeviceReview = model.state { return true }
            return false
        }
        guard case let .needsDeviceReview(review) = model.state else {
            Issue.record("Expected a review for the unknown device.")
            return
        }
        #expect(review.affectedDevices.map(\.id) == [world.otherDeviceID])
        #expect(review.affectedDevices.first?.supportedVersion == nil)
        #expect(try await world.store.deviceDataCapabilities().isEmpty)

        try await world.store.publishDataCapability(
            for: world.otherDeviceID,
            at: DataFeatureAvailabilityTestSupport.now,
        )
        try await CompatibilityPresentationTestSupport.waitUntil {
            if case .available = model.state { return true }
            return false
        }
        #expect(try await world.store.dataCompatibility().requiredVersion == .initial)

        observation.cancel()
        await observation.value
        #expect(model.state == .checking)
    }

    @Test func unsupportedFeatureReportsTheDeviceUpdateRequirement() async throws {
        let store = try SwiftDataStore.inMemory()
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let model = DataFeatureAvailabilityModel(
            requiring: DataFeatureAvailabilityTestSupport.version,
            source: services.compatibility,
        )
        await model.refresh()
        #expect(model.state == .updateRequired(.init(
            supportedVersion: .initial,
            requiredVersion: DataFeatureAvailabilityTestSupport.version,
        )))
        #expect(try await store.dataCompatibility().requiredVersion == .initial)
    }

    @Test func verificationFailureCanBeRetriedWithoutMutation() async throws {
        let store = try TestStore()
        await store.failCompatibilityVerification(true)
        let services = CompatibilityPresentationTestSupport.services(
            store: store,
            source: ScriptedLocationSource(),
        )
        let model = DataFeatureAvailabilityModel(
            requiring: .initial,
            source: services.compatibility,
        )
        await model.refresh()
        guard case .verificationFailed = model.state else {
            Issue.record("A failed preflight must be visible.")
            return
        }
        await store.failCompatibilityVerification(false)
        await model.refresh()
        guard case let .available(review) = model.state else {
            Issue.record("Retry should recover when verification succeeds.")
            return
        }
        #expect(review.requiredVersion == .initial)
        #expect(try await store.deviceDataCapabilities().isEmpty)
    }

    @Test func olderCompletionCannotReplaceANewerWarning() async throws {
        let source = ScriptedDataCompatibilityReviewSource()
        defer { Task { await source.finish() } }
        let model = DataFeatureAvailabilityModel(
            requiring: DataFeatureAvailabilityTestSupport.version,
            source: source,
        )
        let older = Task { await model.refresh() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            await source.requestedVersions.count == 1
        }
        let newer = Task { await model.refresh() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            await source.requestedVersions.count == 2
        }
        let review = DataCompatibilityActivationReview.preview
        await source.complete(request: 1, with: .success(review))
        await newer.value
        #expect(model.state == .needsDeviceReview(review))
        await source.complete(request: 0, with: .success(DataFeatureAvailabilityTestSupport.ready))
        await older.value
        #expect(model.state == .needsDeviceReview(review))
    }

    @Test func storeChangeStartsAFreshCheckWithoutWaitingForTheOldRead() async throws {
        let source = ScriptedDataCompatibilityReviewSource()
        defer { Task { await source.finish() } }
        let model = DataFeatureAvailabilityModel(
            requiring: DataFeatureAvailabilityTestSupport.version,
            source: source,
        )
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            await source.requestedVersions.count == 1
        }
        await source.notifyChange()
        try await CompatibilityPresentationTestSupport.waitUntil {
            await source.requestedVersions.count == 2
        }
        #expect(model.state == .checking)
        let review = DataCompatibilityActivationReview.preview
        await source.complete(request: 1, with: .success(review))
        try await CompatibilityPresentationTestSupport.waitUntil {
            model.state == .needsDeviceReview(review)
        }
        observation.cancel()
        await observation.value
        #expect(model.state == .checking)
        #expect(await source.requestedVersions == [model.requiredVersion, model.requiredVersion])
    }

    @Test func cancelledReadCannotPublishAvailability() async throws {
        let source = ScriptedDataCompatibilityReviewSource()
        defer { Task { await source.finish() } }
        let model = DataFeatureAvailabilityModel(
            requiring: DataFeatureAvailabilityTestSupport.version,
            source: source,
        )
        let refresh = Task { await model.refresh() }
        try await CompatibilityPresentationTestSupport.waitUntil {
            await source.requestedVersions.count == 1
        }
        refresh.cancel()
        await source.complete(request: 0, with: .success(DataFeatureAvailabilityTestSupport.ready))
        await refresh.value
        #expect(model.state == .checking)
    }
}
