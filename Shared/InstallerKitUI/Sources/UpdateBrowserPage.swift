import InstallerKit
import SwiftUI

/// Visibility-scoped refresh and honest cached/error states shared by each browser destination.
struct UpdateBrowserPage<Content: View>: View {
    let model: UpdateModel
    @ViewBuilder let content: Content
    @State private var refresh = UpdatePageRefresh()

    var body: some View {
        UpdatePageLayout {
            UpdateBrowserContent(state: model.state, content: content)
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

private struct UpdateBrowserContent<Content: View>: View {
    let state: UpdateModel.State
    let content: Content

    var body: some View {
        if case let .failed(error, previous) = state {
            UpdateFailureCard(error: error, hasCachedBuilds: previous != nil)
        }
        if state.snapshot != nil {
            content
        } else if case .failed = state {
            EmptyView()
        } else {
            ProgressView(String(localized: .installerChecking))
                .frame(maxWidth: .infinity)
        }
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
