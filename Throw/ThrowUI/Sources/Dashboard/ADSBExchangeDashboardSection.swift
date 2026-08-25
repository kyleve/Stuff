import SFSafeSymbols
import SwiftUI
import ThrowCore

struct ADSBExchangeDashboardSection: View {
    let credentialState: CredentialState
    let intervalSeconds: Int
    let estimate: ADSBExchangeUsageEstimate

    var body: some View {
        Section {
            credentialRow
            LabeledContent(String(localized: .sourceInterval)) {
                Text(
                    Duration.seconds(intervalSeconds),
                    format: .time(pattern: .minuteSecond),
                )
            }
            LabeledContent(String(localized: .sourceRequestsPerHour)) {
                Text(
                    estimate.displayedRequestsPerHour,
                    format: .number,
                )
            }
            LabeledContent(String(localized: .sourceRequests30Days)) {
                Text(
                    estimate.displayedThirtyDayUpperBound,
                    format: .number,
                )
            }
            Text(.sourceAllowance)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if estimate.exceedsPublishedAllowance {
                Label(
                    String(localized: .sourceQuotaWarning),
                    systemSymbol: .exclamationmarkTriangleFill,
                )
                .foregroundStyle(.orange)
            }
            if let dashboardURL = URL(string: "https://rapidapi.com/developer/dashboard") {
                Link(String(localized: .sourceRapidAPIDashboard), destination: dashboardURL)
            }
        } header: {
            Text(.sourceAdsbExchange)
        } footer: {
            Text(.sourceEstimateDisclaimer)
        }
    }

    @ViewBuilder private var credentialRow: some View {
        switch credentialState {
            case .missing:
                Label(
                    String(localized: .sourceCredentialMissing),
                    systemSymbol: .exclamationmarkTriangleFill,
                )
                .foregroundStyle(.red)
            case let .saved(lastFour):
                LabeledContent(String(localized: .sourceCredentialSaved)) {
                    if let lastFour {
                        Text(verbatim: "•••• \(lastFour)")
                            .privacySensitive()
                    } else {
                        Text(.statusConnected)
                    }
                }
        }
    }
}
