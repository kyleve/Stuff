import Foundation
import Inspector
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WhereDeveloperLaunchControllerTests {
    @Test func demoPersistsAndIsConsumedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let configuration = DemoDataBuilder.Configuration(issueCategories: [
            .borderDrift,
            .flightDay,
        ])

        fixture.controller.scheduleDemo(configuration)
        #expect(fixture.reloaded().nextLaunch == .demo(configuration))
        #expect(fixture.controller.consumeDemoConfiguration() == configuration)
        #expect(fixture.controller.nextLaunch == .regularApplication)
        #expect(fixture.reloaded().nextLaunch == .regularApplication)
        #expect(fixture.controller.consumeDemoConfiguration() == nil)
    }

    @Test func inspectorAndDemoSelectionsAreMutuallyExclusive() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        fixture.controller.scheduleDemo(.allIssues)
        fixture.controller.scheduleInspector()
        #expect(fixture.controller.nextLaunch == .inspector)
        #expect(fixture.reloaded().nextLaunch == .inspector)

        fixture.controller.scheduleDemo(.standard)
        #expect(fixture.controller.nextLaunch == .demo(.standard))
        #expect(fixture.controller.inspectorModeController.nextLaunch == .regularApplication)
        #expect(fixture.reloaded().nextLaunch == .demo(.standard))
    }

    @Test func anEmptyIssueSelectionIsAValidScheduledDemo() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let clean = DemoDataBuilder.Configuration(issueCategories: [])

        fixture.controller.scheduleDemo(clean)

        #expect(fixture.reloaded().nextLaunch == .demo(clean))
    }

    @MainActor
    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let controller: WhereDeveloperLaunchController

        init() throws {
            suiteName = "where.developer-launch.\(UUID().uuidString)"
            defaults = try #require(UserDefaults(suiteName: suiteName))
            controller = WhereDeveloperLaunchController(
                userDefaults: defaults,
                inspectorModeController: InspectorModeController(userDefaults: defaults),
            )
        }

        func reloaded() -> WhereDeveloperLaunchController {
            WhereDeveloperLaunchController(
                userDefaults: defaults,
                inspectorModeController: InspectorModeController(userDefaults: defaults),
            )
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
