import SFSafeSymbols
import SwiftUI

struct FeedHealthRow: View {
    let health: FeedHealth

    @Environment(\.throwStylesheet) private var stylesheet

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemSymbol: symbol)
                .foregroundStyle(color)
        }
        .frame(minHeight: stylesheet.status.minimumRowHeight)
    }

    private var title: LocalizedStringResource {
        switch health {
            case .idle: .statusDisconnected
            case .loading: .statusLoading
            case .healthy: .statusHealthy
            case .retrying: .statusRetrying
            case .failed: .statusFailed
            case .quiet: .statusQuiet
        }
    }

    private var detail: String? {
        switch health {
            case let .retrying(_, _, failure, _), let .failed(failure):
                failure.localizedDescription
            case .idle, .loading, .healthy, .quiet:
                nil
        }
    }

    private var symbol: SFSymbol {
        switch health {
            case .healthy: .checkmarkCircleFill
            case .retrying: .arrowCounterclockwise
            case .failed: .xmarkCircleFill
            case .quiet: .moonStarsFill
            case .idle: .circle
            case .loading: .antennaRadiowavesLeftAndRight
        }
    }

    private var color: Color {
        switch health {
            case .healthy: stylesheet.status.healthy
            case .retrying: stylesheet.status.retrying
            case .failed: stylesheet.status.failed
            case .quiet: stylesheet.status.quiet
            case .idle, .loading: .secondary
        }
    }
}
