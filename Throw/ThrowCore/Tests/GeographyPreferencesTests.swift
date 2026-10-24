import Testing
@testable import ThrowCore

struct GeographyPreferencesTests {
    @Test func defaultsEnableARestrainedMap() {
        #expect(GeographyPreferences.defaultValue.isEnabled)
        #expect(GeographyPreferences.defaultValue.intensityPercent == 8)
    }

    @Test(arguments: [-0.1, 20.1, .infinity, .nan])
    func rejectsIntensityOutsideZeroThroughTwenty(_ intensity: Double) {
        #expect(throws: ThrowValidationError.self) {
            try GeographyPreferences(isEnabled: true, intensityPercent: intensity)
        }
    }

    @Test func replacementsPreserveTheOtherValidatedField() throws {
        let disabled = GeographyPreferences.defaultValue.replacingIsEnabled(false)
        let intensified = try disabled.replacingIntensityPercent(12)

        #expect(intensified.isEnabled == false)
        #expect(intensified.intensityPercent == 12)
        #expect(throws: ThrowValidationError.self) {
            try intensified.replacingIntensityPercent(21)
        }
    }
}
