import SFSafeSymbols
import SwiftUI

/// Educational fallback when a live estimated-time panel cannot render.
struct FeatureEstimatedTimeStatusPreview: View {
    enum State {
        case disabled
        case unavailable
    }

    let state: State

    var body: some View {
        FeatureMarketingPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemSymbol: .chartLineUptrendXyaxis)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch state {
            case .disabled:
                String(localized: .settingsExploreEstimatedTimeDisabledTitle)
            case .unavailable:
                String(localized: .settingsExploreEstimatedTimeUnavailableTitle)
        }
    }

    private var message: String {
        switch state {
            case .disabled:
                String(localized: .settingsExploreEstimatedTimeDisabledDescription)
            case .unavailable:
                String(localized: .settingsExploreEstimatedTimeUnavailableDescription)
        }
    }
}

#if DEBUG
    #Preview {
        FeatureEstimatedTimeStatusPreview(state: .unavailable)
            .padding()
            .whereBroadwayRoot()
    }
#endif
