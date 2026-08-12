import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereUI

@MainActor
struct RecordingConfigurationWarningModelTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 100_000)
    private let warning = RecordingConfigurationWarningModel.Configuration(
        isPrimaryRecordingDevice: true,
        automaticRecordingEnabled: false,
        authorizationStatus: .whenInUse,
    )
    @Test func presentsOnlyWhenAllWarningConditionsAreActive() {
        let model = RecordingConfigurationWarningModel(
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        model.register(warning)
        #expect(model.isPresented)

        model.register(RecordingConfigurationWarningModel.Configuration(
            isPrimaryRecordingDevice: true,
            automaticRecordingEnabled: true,
            authorizationStatus: .whenInUse,
        ))
        #expect(model.isPresented == false)

        model.register(RecordingConfigurationWarningModel.Configuration(
            isPrimaryRecordingDevice: true,
            automaticRecordingEnabled: false,
            authorizationStatus: .always,
        ))
        #expect(model.isPresented == false)

        model.register(RecordingConfigurationWarningModel.Configuration(
            isPrimaryRecordingDevice: false,
            automaticRecordingEnabled: false,
            authorizationStatus: .whenInUse,
        ))
        #expect(model.isPresented == false)
    }

    @Test func dismissalPersistsForCurrentGenerationAcrossModels() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let model = RecordingConfigurationWarningModel(preferences: preferences)

        model.register(warning)
        #expect(model.isPresented)
        model.dismiss()

        #expect(model.isPresented == false)
        #expect(RecordingConfigurationWarningModel(preferences: preferences).isPresented == false)
    }

    @Test(arguments: [
        RecordingConfigurationWarningModel.Configuration(
            isPrimaryRecordingDevice: true,
            automaticRecordingEnabled: true,
            authorizationStatus: .whenInUse,
        ),
        RecordingConfigurationWarningModel.Configuration(
            isPrimaryRecordingDevice: true,
            automaticRecordingEnabled: false,
            authorizationStatus: .always,
        ),
    ])
    func warningReappearsAfterEitherRequirementRecoversThenRegresses(
        recovery: RecordingConfigurationWarningModel.Configuration,
    ) {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let model = RecordingConfigurationWarningModel(preferences: preferences)

        model.register(warning)
        model.dismiss()
        model.register(recovery)
        model.register(warning)

        #expect(model.isPresented)
        #expect(preferences.recordingConfigurationWarningRegistration.generation == 2)
    }

    @Test func steadyWarningDoesNotBecomeNewGenerationAfterRelaunch() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let firstModel = RecordingConfigurationWarningModel(preferences: preferences)
        firstModel.register(warning)
        firstModel.dismiss()

        let relaunchedModel = RecordingConfigurationWarningModel(preferences: preferences)
        relaunchedModel.register(warning)

        #expect(relaunchedModel.isPresented == false)
        #expect(preferences.recordingConfigurationWarningRegistration.generation == 1)
    }

    @Test func recentRecorderMakesThisPhoneSecondary() {
        let currentDevice = InstallationRecordingContext.testing.currentDevice
        let otherDevice = RecordingDevice(
            id: RecordingDeviceID(rawValue: UUID()),
            systemName: "Other iPhone",
            nickname: nil,
            kind: .phone,
            registeredAt: Self.now.addingTimeInterval(-100_000),
            lastSeenAt: Self.now,
            removedAt: nil,
            status: .recording,
        )

        #expect(RecordingConfigurationWarningModel.isPrimaryRecordingDevice(
            currentDevice,
            among: [otherDevice],
            now: Self.now,
        ) == false)
        #expect(RecordingConfigurationWarningModel.isPrimaryRecordingDevice(
            currentDevice,
            among: [],
            now: Self.now,
        ))
    }
}
