import PeriscopeCore
import SwiftUI

extension SpanExit.Mode {
    /// Capitalized name shown in chips and the exit filter.
    var displayName: String {
        rawValue.capitalized
    }
}

/// The exit-mode chip shown beside span-ended rows and in event detail.
struct SpanExitBadge: View {
    let mode: SpanExit.Mode

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let badge = stylesheet.badge
        let tint = stylesheet.palette.tint(forSpanExit: mode)
        Text(mode.displayName)
            .font(badge.font)
            .padding(.horizontal, badge.horizontalPadding)
            .padding(.vertical, badge.verticalPadding)
            .background(tint.opacity(badge.backgroundOpacity), in: .capsule)
            .foregroundStyle(tint)
    }
}
