import Foundation
@testable import Inspector
import Testing

@MainActor
struct InspectorModeControllerTests {
    @Test func latchesAndClearsTheNextLaunchSelection() throws {
        let fixture = try DefaultsFixture()
        defer { fixture.cleanup() }

        let controller = InspectorModeController(userDefaults: fixture.defaults)
        #expect(controller.nextLaunch == .regularApplication)

        controller.enterInspectorOnNextLaunch()
        #expect(controller.nextLaunch == .inspector)
        #expect(
            InspectorModeController(userDefaults: fixture.defaults).nextLaunch
                == .inspector,
        )

        controller.useRegularApplicationOnNextLaunch()
        #expect(controller.nextLaunch == .regularApplication)
        #expect(
            InspectorModeController(userDefaults: fixture.defaults).nextLaunch
                == .regularApplication,
        )
    }

    @Test func dedicatedSuiteDoesNotTouchInspectedApplicationDefaults() throws {
        let control = try DefaultsFixture(prefix: "inspector.control")
        let application = try DefaultsFixture(prefix: "inspector.application")
        defer {
            control.cleanup()
            application.cleanup()
        }
        application.defaults.set("kept", forKey: "application-value")

        let controller = InspectorModeController(userDefaults: control.defaults)
        controller.enterInspectorOnNextLaunch()
        application.defaults.removePersistentDomain(forName: application.suiteName)

        #expect(controller.nextLaunch == .inspector)
        #expect(control.defaults.bool(forKey: "inspector.nextLaunch.enabled"))
        #expect(application.defaults.object(forKey: "application-value") == nil)
    }
}

private struct DefaultsFixture {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "inspector.mode") throws {
        suiteName = "\(prefix).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
