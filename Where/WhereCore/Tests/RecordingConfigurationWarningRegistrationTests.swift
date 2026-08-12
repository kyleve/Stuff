import Testing
@testable import WhereCore

struct RecordingConfigurationWarningRegistrationTests {
    @Test func reenteringWarningConditionAdvancesGeneration() {
        var registration = RecordingConfigurationWarningRegistration()

        registration.register(isWarningConditionActive: true)
        #expect(registration.generation == 1)
        #expect(registration.requiresWarning)

        registration.acknowledgeCurrentGeneration()
        registration.register(isWarningConditionActive: true)
        #expect(registration.generation == 1)
        #expect(registration.requiresWarning == false)

        registration.register(isWarningConditionActive: false)
        registration.register(isWarningConditionActive: true)
        #expect(registration.generation == 2)
        #expect(registration.requiresWarning)
    }
}
