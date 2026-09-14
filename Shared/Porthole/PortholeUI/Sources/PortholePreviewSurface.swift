import SwiftUI

/// Uses the production presentation and the fixture awaited by snapshot readiness hooks.
struct PortholePreviewSurface: View {
    @State private var model: PortholePreviewModel

    init(model: PortholePreviewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state {
                case .preparing: ProgressView("Preparing captured issue…")
                case let .ready(controller): PortholeView(controller: controller)
                case let .failed(message): Text(message)
            }
        }
        .task { await model.prepare() }
    }
}
