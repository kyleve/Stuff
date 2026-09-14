import Foundation
import PortholeCore
import Testing

struct PortholeCoveragePageTests {
    @Test func inactiveEvidenceKeepsScopeAndPlannerSupportWithoutAnInstalledCapability() throws {
        let page = PortholeCoveragePage(
            scope: PortholeCoverageTestSupport.scope(),
            total: 1,
            items: [PortholeCoverageTestSupport.entry()],
        )
        let decoded = try PortholeValue.encoding(page).decode(PortholeCoveragePage.self)
        #expect(decoded == page)
        #expect(decoded.items.first?.state == .inactive)
        #expect(decoded.items.first?.declaration.plannedAvailability == .callable)
        #expect(decoded.items.first?.installedCapabilityID == nil)
    }

    @Test(arguments: [
        PortholeCoverageState.callable,
        .inspectableSource,
        .unsupported("No concrete receiver"),
        .inactive,
        .sourceOnly("Native boundary"),
        .excluded("Credential machinery"),
    ])
    func coverageStatesPreserveTheirReasons(state: PortholeCoverageState) throws {
        #expect(try PortholeValue.encoding(state).decode(PortholeCoverageState.self) == state)
    }
}
