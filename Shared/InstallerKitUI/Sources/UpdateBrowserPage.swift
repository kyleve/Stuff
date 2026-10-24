import InstallerKit
import SwiftUI

/// Visibility-scoped refresh and honest cached/error states shared by each browser destination.
struct UpdateBrowserPage<Content: View>: View {
    let model: UpdateModel
    @ViewBuilder let content: Content
    @State private var refresh = UpdatePageRefresh()

    var body: some View {
        UpdatePageLayout {
            if case let .failed(error, previous) = model.state {
                UpdateFailureCard(error: error, hasCachedBuilds: previous != nil)
            }
            if model.state.snapshot != nil {
                content
            } else if case .failed = model.state {
                EmptyView()
            } else {
                ProgressView(String(localized: .installerChecking))
                    .frame(maxWidth: .infinity)
            }
            UpdateCheckButton(isChecking: model.isChecking) {
                refresh.start(model: model)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh(force: false) }
        .refreshable { await refresh.start(model: model).value }
        .onDisappear { refresh.cancel() }
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
