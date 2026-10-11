import Foundation
import RegionKit
import Testing
@_spi(Testing) @testable import WhereCore

struct RecordingDeviceCoordinationTests {
    @Test @MainActor func restoredPhoneRequestsTransferWithoutClaimingExistingOwner() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let authority = RecordingAuthorityCoordinator(store: store, transport: server)
        let oldInstallation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let old = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: oldInstallation,
        )
        let newInstallation = RecordingCoordinationInstallation(deviceID: fixture.tablet)
        let replacement = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: newInstallation,
        )
        _ = try await old.selectRecordingRole(.recordingRequested)
        let requested = try await replacement.selectRecordingRole(.recordingRequested)
        #expect(requested.owner?.deviceID == fixture.phone)
        #expect(requested.pendingHandoff?.requestedBy == fixture.tablet)
        #expect(requested.requiredVersion == .initial)
        #expect(newInstallation.onboardingContext.recordingControl.selection == .recordingRequested)

        let source = ScriptedLocationSource(authorizationStatus: .always)
        let services = WhereServices(
            store: store,
            locationSource: source,
            installationContext: oldInstallation.onboardingContext,
            recordingAuthority: old,
            deviceCoordination: old,
        )
        _ = try await services.recording.register(authorization: .always)
        #expect(await services.ingestor.isActive)
        try await services.recording
            .approveHandoff(requestID: #require(requested.pendingHandoff?.requestID))
        #expect(await services.ingestor.isActive == false)
        #expect(try await authority.observed().owner?.deviceID == fixture.tablet)
        #expect(oldInstallation.onboardingContext.automaticRecordingEnabled == true)
        #expect(oldInstallation.onboardingContext.recordingControl.pendingTransition == nil)
    }

    @Test @MainActor func durableApprovalFencesRecordingAfterRestart() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let server = LocalRecordingAuthorityTransport(now: { Date() })
        let authority = RecordingAuthorityCoordinator(store: store, transport: server)
        let installation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let owned = try await coordination.selectRecordingRole(.recordingRequested)
        let request = try fixture.proposal(owned, .requestHandoff, device: fixture.tablet)
        _ = try await authority.submit(request)
        _ = try await coordination
            .prepareApproval(requestID: #require(request.result.pendingHandoff?.requestID))
        let restarted = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: installation.onboardingContext,
            recordingAuthority: restarted,
            deviceCoordination: restarted,
        )
        _ = try await services.recording.register(authorization: .always)
        #expect(await services.ingestor.isActive == false)
        #expect(try await restarted.isRelinquishing())
    }

    @Test @MainActor func secondaryChoiceNeverClaimsOrEnablesRecording() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let installation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        #expect(try await coordination.selectRecordingRole(.secondary).owner == nil)
        #expect(installation.onboardingContext.automaticRecordingEnabled == false)
        #expect(installation.onboardingContext.recordingControl.selection == .secondary)
    }

    @Test @MainActor func failedStopMarkerCannotTransferAuthority() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let installation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let owned = try await coordination.selectRecordingRole(.recordingRequested)
        let requested = try fixture.proposal(owned, .requestHandoff, device: fixture.tablet)
        _ = try await authority.submit(requested)
        installation.failsControlWrite = true
        await #expect(throws: RecordingCoordinationInstallation.WriteFailure.self) {
            _ = try await coordination
                .prepareApproval(requestID: #require(requested.result.pendingHandoff?.requestID))
        }
        #expect(try await authority.observed().owner?.deviceID == fixture.phone)
    }

    @Test @MainActor func cancelledServerRequestCanClearInterruptedApproval() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let installation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let owned = try await coordination.selectRecordingRole(.recordingRequested)
        let requested = try fixture.proposal(owned, .requestHandoff, device: fixture.tablet)
        _ = try await authority.submit(requested)
        let requestID = try #require(requested.result.pendingHandoff?.requestID)
        let approval = try await coordination.prepareApproval(requestID: requestID)
        _ = try await authority.submit(fixture.proposal(
            requested.result,
            .cancelHandoff(requestID: requestID),
            device: fixture.tablet,
        ))
        await #expect(throws: RecordingAuthorityError.conflict) {
            try await coordination.commitStoppedApproval(approval)
        }
        #expect(try await coordination.isRelinquishing())
        try await coordination.cancelHandoff(requestID: requestID)
        #expect(try await coordination.isRelinquishing() == false)
        #expect(try await authority.observed().owner?.deviceID == fixture.phone)
    }

    @Test @MainActor func formerOwnerFlushesAcceptedBacklogWithoutStartingGPS() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { Date() }),
        )
        let installation = RecordingCoordinationInstallation(deviceID: fixture.phone)
        let coordination = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: installation,
        )
        let owned = try await coordination.selectRecordingRole(.recordingRequested)
        _ = try await authority.submit(fixture.proposal(
            owned,
            .recover(.keep),
            device: fixture.tablet,
        ))
        let sample = LocationSample(
            timestamp: Date(),
            coordinate: Coordinate(latitude: 37.77, longitude: -122.41),
            horizontalAccuracy: 5,
            source: .gpsSignificantChange,
        ).recorded(by: fixture.phone)
        let outbox = ScriptedLocationOutbox([sample])
        let services = WhereServices(
            store: store,
            locationSource: ScriptedLocationSource(authorizationStatus: .always),
            installationContext: installation.onboardingContext,
            recordingAuthority: coordination,
            deviceCoordination: coordination,
            locationOutbox: outbox,
        )
        _ = try await services.recording.register(authorization: .always)
        #expect(await services.ingestor.isActive == false)
        #expect(try await store.samples(in: DateInterval(
            start: sample.timestamp.addingTimeInterval(-1),
            end: sample.timestamp.addingTimeInterval(1),
        )).map(\.id) == [sample.id])
        #expect(await outbox.persistedSamples.isEmpty)
    }

    @Test @MainActor func forcedReplacementUsesServerTimeAndRetainsRawHistory() async throws {
        let fixture = RecordingAuthorityFixture()
        let store = try SwiftDataStore.inMemory()
        let cutoff = Date(timeIntervalSince1970: 2000)
        let authority = RecordingAuthorityCoordinator(
            store: store,
            transport: LocalRecordingAuthorityTransport(now: { cutoff }),
        )
        let old = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: RecordingCoordinationInstallation(deviceID: fixture.phone),
        )
        let owned = try await old.selectRecordingRole(.recordingRequested)
        let owner = try #require(owned.owner)
        let raw = LocationSample(
            timestamp: cutoff.addingTimeInterval(1),
            coordinate: .init(latitude: 40, longitude: -100),
            horizontalAccuracy: 5,
            source: .gpsVisit,
        ).recorded(under: owner)
        try await store.perform { try await store.add(sample: raw) }
        let newInstallation = RecordingCoordinationInstallation(deviceID: fixture.tablet)
        let replacement = RecordingDeviceCoordination(
            supportedVersion: .current,
            authority: authority,
            installation: newInstallation,
        )
        let recovered = try await replacement.recover(
            replacing: owner,
            history: .excludeAfterReplacement,
        )
        #expect(recovered.owner?.deviceID == fixture.tablet)
        #expect(newInstallation.onboardingContext.automaticRecordingEnabled == true)
        #expect(try await store.recordingRecoveryExclusions().first?.replacedAt == cutoff)
        #expect(try await store.allSamples() == [raw])
        #expect(try await LocationHistoryReader(store: store).samples(in: .init(
            start: cutoff,
            end: cutoff.addingTimeInterval(100),
        )).isEmpty)
        await #expect(throws: RecordingAuthorityError.conflict) {
            _ = try await replacement.recover(replacing: owner, history: .keep)
        }
    }
}
