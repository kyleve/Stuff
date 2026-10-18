import InstallerKit
import SwiftUI

/// Visibility-scoped refresh and honest cached/error states shared by each browser destination.
struct UpdateBrowserPage<Content: View>: View {
    let model: UpdateModel
    @ViewBuilder let content: Content
    @State private var manualCheck: Task<Void, Never>?
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdatePageLayout {
            if case .failed = model.state {
                UpdateCard(title: .installerCheckFailed) {
                    Text(.installerCheckFailedMessage)
                        .font(stylesheet.card.bodyFont)
                        .foregroundStyle(.secondary)
                }
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
