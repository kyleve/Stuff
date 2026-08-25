import SwiftUI

struct ProjectionStatusIndicator: View {
    let health: FeedHealth

    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        switch health {
            case let .retrying(_, _, _, visibleAircraft) where visibleAircraft > 0:
                Circle()
                    .stroke(stylesheet.status.retrying, lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .opacity(stylesheet.projection.statusLuminance)
                    .accessibilityHidden(true)
            case .retrying, .failed:
                Rectangle()
                    .fill(stylesheet.status.failed)
                    .frame(width: 12, height: 12)
                    .opacity(stylesheet.projection.statusLuminance)
                    .accessibilityHidden(true)
            case .idle, .loading, .healthy, .quiet:
                EmptyView()
        }
    }
}
