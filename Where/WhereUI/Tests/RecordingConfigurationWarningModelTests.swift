import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct RecordingConfigurationWarningModelTests {
    @Test func presentsWhenConditionBecomesActive() {
        let model = RecordingConfigurationWarningModel(
            preferences: WherePreferences(store: InMemoryKeyValueStore()),
        )

        model.register(isWarningConditionActive: true)
        #expect(model.isPresented)

        model.register(isWarningConditionActive: false)
        #expect(model.isPresented == false)
    }

    @Test func dismissalPersistsForCurrentGenerationAcrossModels() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let model = RecordingConfigurationWarningModel(preferences: preferences)

        model.register(isWarningConditionActive: true)
        #expect(model.isPresented)
        model.dismiss()

        #expect(model.isPresented == false)
        #expect(RecordingConfigurationWarningModel(preferences: preferences).isPresented == false)
    }

    @Test func warningReappearsAfterConditionRecoversThenRegresses() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let model = RecordingConfigurationWarningModel(preferences: preferences)

        model.register(isWarningConditionActive: true)
        model.dismiss()
        model.register(isWarningConditionActive: false)
        model.register(isWarningConditionActive: true)

        #expect(model.isPresented)
        #expect(preferences.recordingConfigurationWarningRegistration.generation == 2)
    }

    @Test func steadyWarningDoesNotBecomeNewGenerationAfterRelaunch() {
        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        let firstModel = RecordingConfigurationWarningModel(preferences: preferences)
        firstModel.register(isWarningConditionActive: true)
        firstModel.dismiss()

        let relaunchedModel = RecordingConfigurationWarningModel(preferences: preferences)
        relaunchedModel.register(isWarningConditionActive: true)

        #expect(relaunchedModel.isPresented == false)
        #expect(preferences.recordingConfigurationWarningRegistration.generation == 1)
    }
}
