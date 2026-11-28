import Observation
import SwiftUI

/// Creates a screen's observable model after the host mounts and retains it
/// for that SwiftUI view identity. The content closure receives the ready model.
///
/// Pass a synchronous factory so SwiftUI can rebuild the host without rebuilding the model:
///
/// ```swift
/// ObservableHostingView {
///     DetailModel(itemID: itemID)
/// } content: { model in
///     DetailView(model: model)
/// }
/// ```
///
/// A changed factory keeps the existing model. Apply `.id(itemID)` to the host
/// when a different item needs a fresh model. Own cross-screen drafts in their flow.
struct ObservableHostingView<Model: Observable, Content: View>: View {
    private let makeModel: () -> Model
    private let content: (Model) -> Content
    @State private var model: Model?

    init(_ makeModel: @escaping () -> Model, @ViewBuilder content: @escaping (Model) -> Content) {
        self.makeModel = makeModel
        self.content = content
    }

    var body: some View {
        if let model {
            content(model)
        } else {
            Color.clear.task {
                guard model == nil else { return }
                model = makeModel()
            }
        }
    }
}

#if DEBUG
    @Observable
    private final class ObservableHostingPreviewModel {
        var step = 1
    }

    #Preview {
        ObservableHostingView {
            ObservableHostingPreviewModel()
        } content: { model in
            VStack {
                Text(model.step, format: .number)
                Button(String(localized: .onboardingNext)) { model.step += 1 }
            }
        }
    }
#endif
