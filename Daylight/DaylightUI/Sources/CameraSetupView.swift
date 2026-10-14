import DaylightCore
import SwiftUI

struct CameraSetupView: View {
    @Bindable var model: DaylightModel
    @Environment(\.daylightStylesheet) private var stylesheet
    @Environment(\.scenePhase) private var scenePhase
    private struct PreviewLifecycle: Equatable {
        let key: DaylightModel.PreviewKey; let active: Bool
    }

    var body: some View {
        VStack {
            Group {
                if let image = model
                    .previewImage { Image(uiImage: image).resizable().scaledToFit() }
                else {
                    Rectangle().fill(stylesheet.preview.background)
                        .overlay { Text(.cameraPreview).foregroundStyle(.white) }
                }
            }
            .aspectRatio(stylesheet.preview.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: stylesheet.preview.cornerRadius))
            .accessibilityLabel(Text(.cameraPreview))
            Text(.cameraRawAutomatic).font(.footnote).foregroundStyle(.secondary)
            Picker(selection: $model.settings.camera.lens) {
                ForEach(model.lenses, id: \.self) { lens in Text(lens.title).tag(lens) }
            } label: { Text(.cameraLens) }
            LabeledContent { Text(
                model.settings.camera.zoom,
                format: .number.precision(.fractionLength(1)),
            ) } label: { Text(.cameraZoom) }
            Slider(value: $model.settings.camera.zoom, in: 1 ... 10) { Text(.cameraZoom) }
            LabeledContent { Text(
                model.settings.camera.exposureBias,
                format: .number.precision(.fractionLength(1)),
            ) } label: { Text(.cameraExposure) }
            Slider(value: $model.settings.camera.exposureBias, in: -3 ... 3) {
                Text(.cameraExposure)
            }
        }
        .task(id: PreviewLifecycle(key: model.previewKey, active: scenePhase == .active)) {
            if scenePhase == .active { await model.preview() }
        }
    }
}

#if DEBUG
    #Preview { CameraSetupView(model: DaylightPreviewSupport.model()).padding() }
#endif
