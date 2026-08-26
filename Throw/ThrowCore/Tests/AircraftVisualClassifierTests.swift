import Testing
@testable import ThrowCore

struct AircraftVisualClassifierTests {
    struct FamilyCase: CustomTestStringConvertible {
        let designator: String
        let category: AircraftEmitterCategory
        let expected: AircraftVisualFamily

        var testDescription: String {
            designator
        }
    }

    private let classifier = AircraftVisualClassifier(catalog: .bundled)

    @Test(arguments: [
        FamilyCase(designator: "B748", category: .heavy, expected: .heavyJet),
        FamilyCase(designator: "B738", category: .large, expected: .airliner),
        FamilyCase(designator: "E75L", category: .large, expected: .regionalBusinessJet),
        FamilyCase(designator: "C172", category: .light, expected: .propeller),
        FamilyCase(designator: "A109", category: .rotorcraft, expected: .helicopter),
    ])
    func catalogAndOverridesSelectStableFamilies(_ value: FamilyCase) {
        #expect(
            classifier.family(
                designator: AircraftTypeDesignator(rawValue: value.designator),
                emitterCategory: value.category,
            ) == value.expected,
        )
    }

    @Test func categoryProvidesAHintWhenTypeIsMissing() {
        #expect(classifier.family(designator: nil, emitterCategory: .heavy) == .heavyJet)
        #expect(classifier.family(designator: nil, emitterCategory: .rotorcraft) == .helicopter)
        #expect(classifier.family(designator: nil, emitterCategory: nil) == .unknown)
    }

    @Test func contradictoryMetadataFallsBackToUnknown() {
        #expect(
            classifier.family(
                designator: AircraftTypeDesignator(rawValue: "B738"),
                emitterCategory: .rotorcraft,
            ) == .unknown,
        )
    }

    @Test func descriptorUsesOnlyCuratedDirectCarrierPrefixes() throws {
        let united = try ThrowCoreFixture.observation(callsign: "UAL123")
        let affiliate = try ThrowCoreFixture.observation(callsign: "SKW4321")

        #expect(classifier.descriptor(for: united).brand == .united)
        #expect(classifier.descriptor(for: affiliate).brand == nil)
    }

    @Test func explicitCarrierDesignatorDoesNotDependOnDisplayFlightNumber() throws {
        let observation = try ThrowCoreFixture.observation(
            callsign: "UA817",
            airlineDesignator: "UAL",
        )

        #expect(classifier.descriptor(for: observation).brand == .united)
    }
}
