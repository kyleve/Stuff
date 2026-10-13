import Foundation
import PeriscopeCore
import Testing
@testable import WhereUI

struct PlanningRegionSelectionModelLogTests {
    @Test func loadFailureRetainsStructuredDetailsLocallyAndExcludesThemFromBaseline() throws {
        let original = NSError(
            domain: "PlanningStore",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Private store path could not be opened"],
        )
        let event = PlanningRegionSelectionModelLog.LoadFailed(
            error: .restricted(.errorDetails, original),
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(
            PlanningRegionSelectionModelLog.LoadFailed.self,
            from: data,
        )

        #expect(PlanningRegionSelectionModelLog.LoadFailed
            .eventName == "PlanningRegions.load-failed")
        #expect(PlanningRegionSelectionModelLog.LoadFailed.eventVersion == 2)
        #expect(decoded.level == .warning)
        #expect(decoded.error == LogError(capturing: original))
        #expect(decoded.classifiedFields == [
            .restricted(key: LogFieldKey("error"), kind: .errorDetails),
        ])
        #expect(try decoded.exportedValue(using: .init(
            mode: .baseline,
            enabledControls: [],
        )) == .object([:]))
    }
}
