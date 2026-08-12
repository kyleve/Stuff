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

#if DEBUG
    #Preview {
        let session = PreviewSupport.loadedSession()
        let model = PreviewSupport.recordingConfigurationWarningModel()
        TabView(selection: .constant(0)) {
            Tab(value: 0) {
                Color.clear
            } label: {
                RecordingConfigurationWarningTabLabel(
                    model: model,
                    source: RecordingConfigurationWarningModel.Source(session: session),
                )
            }
            .badge(model.isPresented ? 1 : 0)
        }
    }
#endif
