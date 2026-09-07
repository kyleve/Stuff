@testable import DaylightUI
import Testing

@MainActor
struct DaylightModelTests {
    @Test func loadsFromInjectedServicesAndPersistsSettings() async {
        let model = DaylightPreviewSupport.model()
        await model.load()
        #expect(model.ready)
        #expect(model.history.count == 1)
        #expect(!model.isArmed)
        model.settings.camera.zoom = 2
        await model.saveSettings()
        #expect(model.notice == nil)
    }

    @Test func stoppingReturnsToSetup() async {
        let model = DaylightModel.preview(mode: .armed, notice: nil)
        await model.toggleArmed()
        #expect(!model.isArmed)
    }
}
