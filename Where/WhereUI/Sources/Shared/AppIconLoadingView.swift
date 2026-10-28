import SwiftUI

/// A centered, full-area "working" state: the shared `AppIconActivityIndicator`
/// (the user's selected app icon breathing gently) above a caption. The single
/// loading treatment for whole-view waits — a first data load, an in-progress
/// scan, a summary generating — so they share one look and one accessibility
/// shape instead of each rebuilding a spinner-plus-label.
struct AppIconLoadingView: View {
    @Environment(\.primaryAppIconName) private var primaryAppIconName

    let caption: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(spacing: stylesheet.spacing.xxLarge) {
            AppIconActivityIndicator(primaryAppIconName: primaryAppIconName)
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
    }
}

#if DEBUG
    #Preview {
        AppIconLoadingView(caption: "Charting your year…")
    }
#endif
