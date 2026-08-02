import Foundation
@testable import Inspector
import Testing

@MainActor
struct InspectorModeControllerFixture {
    let suiteName: String
    let defaults: UserDefaults
    let controller: InspectorModeController

    init(prefix: String = "inspector.control") throws {
        suiteName = "\(prefix).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        controller = InspectorModeController(userDefaults: defaults)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
