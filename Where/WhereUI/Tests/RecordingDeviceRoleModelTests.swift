import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct RecordingDeviceRoleModelTests {
    @Test(arguments: [true, false])
    func blockedUpgradeCanCancelAnUncommittedHandoff(approval: Bool) async throws {
        let bootstrap = try CompatibilityBootstrap()
        let owner = try await bootstrap.recording.selectRecordingRole(.recordingRequested)
        let request = try RecordingAuthorityProposal(
            state: owner,
            action: .requestHandoff,
            deviceID: .init(rawValue: UUID()),
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        _ = try await bootstrap.authority.submit(request)
        let requestID = try #require(request.result.pendingHandoff?.requestID)
        let context = try bootstrap.installation.resolve()
        let pending = try RecordingAuthorityProposal(
            state: request.result,
            action: approval ? .approveHandoff(requestID: requestID) :
                .cancelHandoff(requestID: requestID),
            deviceID: context.currentDevice.id,
            buildVersion: .current,
            eventID: .init(rawValue: UUID()),
        )
        try bootstrap.installation.setRecordingControl(.init(
            selection: .recordingRequested,
            pendingTransition: pending,
        ))
        // Relaunch a newer build after persisting the command, before its server commit.
        let version = DataCompatibilityVersion(rawValue: 2)
        let recording = RecordingDeviceCoordination(
            supportedVersion: version,
            authority: bootstrap.authority,
            installation: bootstrap.installation,
        )
        let compatibility = DataCompatibilityCoordinator(
            store: bootstrap.store,
            recording: recording,
            installation: bootstrap.installation,
        )
        guard case .verificationFailed = await compatibility.recheck() else {
            Issue.record("The unresolved command must prevent an automatic upgrade.")
            return
        }
        let role = RecordingDeviceRoleModel(
            coordination: recording,
            currentDeviceID: context.currentDevice.id,
            selectionChanged: nil,
            approve: nil,
        )
        await role.refresh()
        #expect(role.isOwner)
        #expect(!role.canApprove)
        #expect(role.state.details?.interruptedApproval == requestID)
        await role.cancelRequest()
        #expect(try bootstrap.installation.resolve().recordingControl.pendingTransition == nil)
        #expect(await compatibility.recheck() == .compatible(version))
        let resolved = try await recording.observed()
        #expect(resolved.owner == owner.owner)
        #expect(resolved.pendingHandoff == nil)
        #expect(bootstrap.makeServicesCount == 0)
    }

    @Test func waitingRequestUpdatesLocalConsentWithoutCompletingOnboarding() async throws {
        let installation = InMemoryInstallationRecordingContextStore(context: .testing)
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
            installation: InMemoryInstallationRecordingContextStore(context: .testing),
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
            installation: InMemoryInstallationRecordingContextStore(context: .testing),
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
