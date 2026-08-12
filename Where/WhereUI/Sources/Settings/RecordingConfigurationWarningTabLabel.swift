import SwiftUI

/// Settings tab label that owns the warning badge's refresh lifecycle and accessible meaning.
struct RecordingConfigurationWarningTabLabel: View {
    let model: RecordingConfigurationWarningModel
    let source: RecordingConfigurationWarningModel.Source

    var body: some View {
        let inputs = source.localInputs
        Label(String(localized: .tabSettings), systemImage: "gearshape.fill")
            .accessibilityValue(
                model.isPresented ? String(localized: .settingsRecordingWarningTitle) : "",
            )
            .task(id: inputs) {
                await model.refresh(inputs, from: source)
            }
            .task {
                await model.observeAuthorityChanges(from: source)
            }
    }
}
