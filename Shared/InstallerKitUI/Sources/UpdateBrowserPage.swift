import InstallerKit
import SwiftUI

/// Visibility-scoped refresh and honest cached/error states shared by each browser destination.
struct UpdateBrowserPage<Content: View>: View {
    let model: UpdateModel
    @ViewBuilder let content: Content
    @State private var manualCheck: Task<Void, Never>?

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
                manualCheck?.cancel()
                manualCheck = Task { await model.refresh(force: true) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh(force: false) }
        .refreshable { await model.refresh(force: true) }
        .onDisappear {
            manualCheck?.cancel()
            manualCheck = nil
        }
    }
}

#if DEBUG
    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
