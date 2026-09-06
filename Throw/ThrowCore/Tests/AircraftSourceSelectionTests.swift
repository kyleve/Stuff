import Testing
@testable import ThrowCore

struct AircraftSourceSelectionTests {
    @Test func legacyPairsMapToOneValidSelectionState() throws {
        #expect(try AircraftSourceSelection(
            selectedSource: nil,
            validatedSource: nil,
        ) == .unconfigured)
        #expect(try AircraftSourceSelection(
            selectedSource: .adsbLol,
            validatedSource: nil,
        ) == .awaitingValidation(.adsbLol))
        #expect(try AircraftSourceSelection(
            selectedSource: .adsbLol,
            validatedSource: .adsbLol,
        ) == .configured(.adsbLol))
    }

    @Test func legacyPairRejectsDifferentSelectedAndValidatedSources() {
        #expect(throws: ThrowValidationError.invalidPreferencePayload) {
            try AircraftSourceSelection(
                selectedSource: .adsbLol,
                validatedSource: .adsbExchangeRapidAPI(
                    ADSBExchangeConfiguration(
                        pollingInterval: PollingInterval.defaultValue,
                    ),
                ),
            )
        }
    }
}
