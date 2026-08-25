import SFSafeSymbols
import SwiftUI

struct LocationHealthRow: View {
    let health: LocationHealth

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(title)
                if case let .confirmed(accuracy, acceptedAt) = health {
                    LocationDetailView(accuracyMeters: accuracy, acceptedAt: acceptedAt)
                } else if case let .stale(accuracy, acceptedAt) = health {
                    LocationDetailView(accuracyMeters: accuracy, acceptedAt: acceptedAt)
                } else if case let .offeredBest(accuracy, observedAt, _) = health {
                    LocationDetailView(accuracyMeters: accuracy, acceptedAt: observedAt)
                }
            }
        } icon: {
            Image(systemSymbol: symbol)
                .foregroundStyle(color)
        }
    }

    private var title: LocalizedStringResource {
        switch health {
            case .missing: .locationMissing
            case .locating: .locationLocating
            case .offeredBest: .locationOfferedBest
            case .confirmed: .locationConfirmed
            case .stale: .locationStale
            case .failed: .locationFailed
        }
    }

    private var symbol: SFSymbol {
        switch health {
            case .confirmed: .locationFill
            case .stale, .offeredBest: .exclamationmarkTriangle
            case .missing, .failed: .locationSlash
            case .locating: .locationMagnifyingglass
        }
    }

    private var color: Color {
        switch health {
            case .confirmed: .green
            case .stale, .offeredBest: .orange
            case .failed: .red
            case .missing, .locating: .secondary
        }
    }
}
