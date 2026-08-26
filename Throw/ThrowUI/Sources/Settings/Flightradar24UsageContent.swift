import SFSafeSymbols
import SwiftUI
import ThrowCore

struct Flightradar24UsageContent: View {
    @Bindable var model: AircraftSourceSettingsModel

    var body: some View {
        switch model.flightradar24UsageState {
            case .idle:
                if case .missing = model.credentialState {
                    Text(.sourceFr24NoSavedUsage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .loading:
                HStack {
                    ProgressView()
                    Text(.sourceFr24LoadingUsage)
                }
            case let .loaded(report):
                LabeledContent(String(localized: .sourceFr24RecentRequests)) {
                    Text(report.requestCount, format: .number)
                }
                LabeledContent(String(localized: .sourceFr24RecentCredits)) {
                    Text(report.credits, format: .number)
                }
                if let estimate = model.flightradar24CreditEstimate {
                    LabeledContent(String(localized: .sourceFr24AverageCredits)) {
                        Text(
                            estimate.averageCreditsPerRequest,
                            format: .number.precision(.fractionLength(1)),
                        )
                    }
                    LabeledContent(String(localized: .sourceFr24ProjectedCreditsHour)) {
                        Text(
                            estimate.creditsPerActiveHour,
                            format: .number.precision(.fractionLength(0)),
                        )
                    }
                    LabeledContent(String(localized: .sourceFr24ProjectedCredits30Days)) {
                        Text(
                            estimate.thirtyDayUpperBound,
                            format: .number.precision(.fractionLength(0)),
                        )
                    }
                } else {
                    Text(.sourceFr24NoRecentUsage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .rateLimited:
                Label(
                    String(localized: .sourceFr24UsageRateLimited),
                    systemSymbol: .clock,
                )
                .foregroundStyle(.secondary)
                retryButton
            case .unexpectedResponse:
                Label(
                    String(localized: .sourceFr24UsageUnexpectedResponse),
                    systemSymbol: .exclamationmarkTriangleFill,
                )
                .foregroundStyle(.red)
                retryButton
            case let .failed(failure):
                Label(failure.localizedDescription, systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.red)
                retryButton
        }
    }

    private var retryButton: some View {
        Button(
            String(localized: .commonRetry),
            systemSymbol: .arrowClockwise,
        ) {
            Task(name: "Throw retry FR24 usage") {
                await model.loadFlightradar24Usage()
            }
        }
    }
}

#if DEBUG
    #Preview("Recent FR24 usage") {
        let session = ThrowSession.fixture()
        let model = AircraftSourceSettingsModel(session: session)
        model.choice = .flightradar24
        model.pollingIntervalSeconds = 300
        model.flightradar24UsageState = .loaded(
            Flightradar24UsageReport(
                period: .last24Hours,
                requestCount: 12,
                credits: 2400,
            ),
        )
        return Form {
            Flightradar24CadenceSection(model: model)
        }
        .throwBroadwayRoot()
    }
#endif
