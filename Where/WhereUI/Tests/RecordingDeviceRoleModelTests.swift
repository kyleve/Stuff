import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingDeviceRoleModelTests {
    @Test func waitingRequestUpdatesLocalConsentWithoutCompletingOnboarding() async throws {
        let installation = InMemoryInstallationRecordingContextStore(context: .testing)
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let other = RecordingDeviceID(rawValue: UUID())
        let claim = try RecordingAuthorityProposal(
            state: .initial,
            action: .claim,
            deviceID: other,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        _ = try await authority.submit(claim)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        var selected: Bool?
        let model = RecordingDeviceRoleModel(
            coordination: coordination,
            currentDeviceID: installation.onboardingContext.currentDevice.id,
            selectionChanged: { selected = $0 },
            approve: nil,
        )
        await model.refresh()
        #expect(await model.choose(recording: true) == nil)
        #expect(selected == true)
        #expect(model.state.details?.isWaiting == true)
        #expect(model.isOwner == false)
        #expect(try await authority.observed().owner?.deviceID == other)
        #expect(await model.choose(recording: false) == false)
        #expect(selected == false)
        #expect(model.state.details?.isWaiting == false)
    }

    @Test func recoveryRequiresTheReviewedOwnerToRemainCurrent() async throws {
        let installation = InMemoryInstallationRecordingContextStore(context: .testing)
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let other = RecordingDeviceID(rawValue: UUID())
        let claim = try RecordingAuthorityProposal(
            state: .initial,
            action: .claim,
            deviceID: other,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        _ = try await authority.submit(claim)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let model = RecordingDeviceRoleModel(
            coordination: coordination,
            currentDeviceID: installation.onboardingContext.currentDevice.id,
            selectionChanged: { _ in },
            approve: nil,
        )
        await model.refresh()
        model.reviewRecovery()
        let replacement = RecordingDeviceID(rawValue: UUID())
        _ = try await authority.submit(RecordingAuthorityProposal(
            state: claim.result,
            action: .recover(.keep),
            deviceID: replacement,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        ))
        await model.recover(history: .excludeAfterReplacement)
        #expect(try await authority.observed().owner?.deviceID == replacement)
        #expect(!model.isOwner)
        #expect(model.recoveryReview == nil)
    }
}
