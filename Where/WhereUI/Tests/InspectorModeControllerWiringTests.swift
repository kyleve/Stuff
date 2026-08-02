import Foundation
import Inspector
import Testing

@MainActor
struct InspectorModeControllerWiringTests {
    @Test func selectingAndCancellingInspectorPersistsAcrossControllers() throws {
        let suiteName = "where.ui.inspector-mode.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = InspectorModeController(userDefaults: defaults)
        #expect(first.nextLaunch == .regularApplication)

        first.enterInspectorOnNextLaunch()
        #expect(first.nextLaunch == .inspector)
        #expect(InspectorModeController(userDefaults: defaults).nextLaunch == .inspector)

        first.useRegularApplicationOnNextLaunch()
        #expect(first.nextLaunch == .regularApplication)
        #expect(
            InspectorModeController(userDefaults: defaults).nextLaunch
                == .regularApplication,
        )
    }
}
