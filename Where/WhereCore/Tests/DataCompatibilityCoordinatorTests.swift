import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataCompatibilityCoordinatorTests {
    @Test func secondaryUpdatePublishesSupportWithoutUpgradingSharedData() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        try await world.coordinator.publishCapability(at: CompatibilityTestSupport.now)
        #expect(try await world.coordinator.status().requiredVersion == .initial)
        #expect(try await world.store.deviceDataCapabilities().first?
            .supportedVersion == CompatibilityTestSupport.nextVersion)
        let review = try await world.coordinator
            .reviewActivation(requiring: CompatibilityTestSupport.nextVersion)
        #expect(review.affectedDevices.map(\.id) == [world.phone])
        #expect(review.affectedDevices.first?.supportedVersion == nil)
        await #expect(throws: DataCompatibilityError.confirmationRequired(review)) {
            try await world.coordinator.perform(
                requiring: CompatibilityTestSupport.nextVersion,
                approval: .readyDevicesOnly,
            ) {}
        }
        // Deferring the new feature must leave ordinary writes and reads available.
        let sample = CompatibilityTestSupport.sample
        try await world.store.perform { try await world.store.add(sample: sample) }
        #expect(try await world.store.allSamples() == [sample])
        #expect(try await world.coordinator.status().requiredVersion == .initial)
    }

    @Test func allDevicesReadyAllowsAtomicActivationAndRepeatedUse() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        // Readiness does not expire while a device is offline.
        try await world.store.publishDataCapability(for: world.phone, at: .distantPast)
        let sample = CompatibilityTestSupport.sample
        try await world.coordinator.perform(
            requiring: CompatibilityTestSupport.nextVersion,
            approval: .readyDevicesOnly,
        ) {
            try await world.store.add(sample: sample)
        }
        #expect(try await world.coordinator.status().requiredVersion == CompatibilityTestSupport
            .nextVersion)
        #expect(try await world.store.allSamples() == [sample])
        try await world.coordinator.perform(requiring: .initial, approval: .readyDevicesOnly) {}
        #expect(try await world.coordinator.status().requiredVersion == CompatibilityTestSupport
            .nextVersion)
    }

    @Test func overrideAuthorizesOnlyTheReviewedTransition() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        let version = CompatibilityTestSupport.nextVersion
        let review = try await world.coordinator.reviewActivation(requiring: version)
        try await world.coordinator
            .perform(requiring: version, approval: .continueAnyway(review)) {}
        await world.store.setSupportedDataCompatibilityVersionForTesting(.initial)
        let status = try await world.coordinator.status()
        #expect(!status.isCompatible)
        await #expect(throws: DataCompatibilityError.updateRequired(status)) {
            try await world.coordinator.perform(
                requiring: version,
                approval: .continueAnyway(review),
            ) {}
        }
    }

    @Test func changedWarningReturnsAFreshReview() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        let version = CompatibilityTestSupport.nextVersion
        let oldReview = try await world.coordinator.reviewActivation(requiring: version)
        await world.store.setSupportedDataCompatibilityVersionForTesting(.initial)
        try await world.store.publishDataCapability(
            for: world.phone,
            at: CompatibilityTestSupport.now,
        )
        await world.store.setSupportedDataCompatibilityVersionForTesting(version)
        let newReview = try await world.coordinator.reviewActivation(requiring: version)
        #expect(newReview != oldReview)
        await #expect(throws: DataCompatibilityError.confirmationRequired(newReview)) {
            try await world.coordinator.perform(
                requiring: version,
                approval: .continueAnyway(oldReview),
            ) {}
        }
        #expect(try await world.coordinator.status().requiredVersion == .initial)
    }

    @Test func failedDependentWriteRollsBackRequirement() async throws {
        struct WriteFailure: Error {}
        let world = try await CompatibilityTestSupport.makeWorld()
        let review = try await world.coordinator
            .reviewActivation(requiring: CompatibilityTestSupport.nextVersion)
        await #expect(throws: WriteFailure.self) {
            try await world.coordinator.perform(
                requiring: review.requiredVersion,
                approval: .continueAnyway(review),
            ) {
                try await world.store.add(sample: CompatibilityTestSupport.sample)
                throw WriteFailure()
            }
        }
        #expect(try await world.coordinator.status().requiredVersion == .initial)
        #expect(try await world.store.allSamples().isEmpty)
    }

    @Test func removedDevicesDoNotDelayActivation() async throws {
        let world = try await CompatibilityTestSupport.makeWorld()
        try await world.store.perform {
            try await world.store.addRecordingDeviceRemoval(.init(
                id: .init(rawValue: UUID()),
                deviceID: world.phone,
                removedAt: CompatibilityTestSupport.now,
                removedByDeviceID: world.secondary,
            ))
        }
        #expect(try await !world.coordinator
            .reviewActivation(requiring: CompatibilityTestSupport.nextVersion).requiresConfirmation)
    }
}
