import SFSafeSymbols
import SwiftUI

struct HomeWidgetEmptyState: View {
    let symbol: SFSymbol
    let title: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Image(systemSymbol: symbol)
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview {
        HomeWidgetEmptyState(symbol: .locationSlash, title: String(localized: .widgetTodayEmpty))
            .whereBroadwayRoot()
    }
#endif
