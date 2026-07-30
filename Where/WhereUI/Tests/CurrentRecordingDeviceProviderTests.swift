import Foundation
import Testing
@testable import WhereUI

@MainActor
struct CurrentRecordingDeviceProviderTests {
    @Test func persistsOneInstallationIdentity() throws {
        let suiteName = "CurrentRecordingDeviceProviderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = CurrentRecordingDeviceProvider.current(defaults: defaults)
        let second = CurrentRecordingDeviceProvider.current(defaults: defaults)

        #expect(first == second)
        #expect(defaults.dictionaryRepresentation().values.contains {
            ($0 as? String) == first.id.rawValue.uuidString
        })
        #expect(first.systemName.isEmpty == false)
    }
}
