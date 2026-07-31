import Foundation
import Testing
@testable import WhereUI

@MainActor
struct CurrentRecordingDeviceProviderTests {
    @Test func phonePersistsOneInstallationIdentityAndDefaultsOn() throws {
        let suiteName = "CurrentRecordingDeviceProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = CurrentRecordingDeviceProvider.participation(
            defaults: defaults,
            idiom: .phone,
        )
        let second = CurrentRecordingDeviceProvider.participation(
            defaults: defaults,
            idiom: .phone,
        )
        let firstDevice = try #require(first.currentDevice)

        #expect(first == second)
        #expect(first.defaultEnabledForNewInstallation)
        #expect(defaults.dictionaryRepresentation().values.contains {
            ($0 as? String) == firstDevice.id.rawValue.uuidString
        })
        #expect(firstDevice.systemName.isEmpty == false)
    }

    @Test func tabletParticipatesButDefaultsOff() throws {
        let suiteName = "CurrentRecordingDeviceProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let participation = CurrentRecordingDeviceProvider.participation(
            defaults: defaults,
            idiom: .pad,
        )

        #expect(participation.currentDevice?.kind == .tablet)
        #expect(participation.defaultEnabledForNewInstallation == false)
    }

    @Test func macIsManagementOnlyAndDoesNotMintAnIdentity() throws {
        let suiteName = "CurrentRecordingDeviceProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let participation = CurrentRecordingDeviceProvider.participation(
            defaults: defaults,
            idiom: .mac,
        )

        #expect(participation == .managementOnly)
        let persistedDefaults = defaults.persistentDomain(forName: suiteName) ?? [:]
        #expect(persistedDefaults.isEmpty)
    }

    @Test func demoKeepsAManagementOnlyHostManagementOnly() {
        let participation = CurrentRecordingDeviceProvider.demoParticipation(
            supportsLocalRecording: false,
        )

        #expect(participation == .managementOnly)
    }

    #if targetEnvironment(macCatalyst)
        @Test func catalystDemoUsesManagementOnlyParticipationForItsCurrentHost() {
            #expect(
                CurrentRecordingDeviceProvider.demoParticipationForCurrentHost
                    == .managementOnly,
            )
        }
    #endif
}
