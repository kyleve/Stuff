import Testing
@testable import ThrowCore

struct AircraftVisualModelsTests {
    @Test func familySizeMultipliersStayWithinTheDesignedRange() {
        for family in AircraftVisualFamily.allCases {
            #expect((0.9 ... 1.15).contains(family.sizeMultiplier))
        }
        #expect(
            AircraftVisualFamily.heavyJet.sizeMultiplier >
                AircraftVisualFamily.airliner.sizeMultiplier,
        )
    }

    @Test func carrierMatchingRequiresAnExactCuratedICAOPrefix() {
        #expect(AirlineBrand.identify(callsign: "  dal308 ") == .delta)
        #expect(AirlineBrand.identify(callsign: "AMAZON") == nil)
        #expect(AirlineBrand.identify(callsign: "SKW1") == nil)
        #expect(AirlineBrand.identify(callsign: nil) == nil)
    }
}
