import SFSafeSymbols
import SwiftUI

struct RapidAPICadenceSection: View {
    @Bindable var model: AircraftSourceSettingsModel

    var body: some View {
        Section {
            LabeledContent(String(localized: .sourceInterval)) {
                Text(
                    Duration.seconds(model.pollingIntervalSeconds),
                    format: .time(pattern: .minuteSecond),
                )
            }
            Slider(value: $model.pollingIntervalSeconds, in: 5 ... 300, step: 1)
                .accessibilityLabel(Text(.sourceInterval))
                .accessibilityValue(
                    Text(
                        Duration.seconds(Int(model.pollingIntervalSeconds)),
                        format: .time(pattern: .minuteSecond),
                    ),
                )
            LabeledContent(String(localized: .sourceRequestsPerHour)) {
                Text(model.requestsPerHour, format: .number)
            }
            LabeledContent(String(localized: .sourceRequests30Days)) {
                Text(model.thirtyDayUpperBound, format: .number)
            }
            Text(.sourceAllowance)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(.sourceUsageExamples)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.exceedsPublishedAllowance {
                Label(
                    String(localized: .sourceQuotaWarning),
                    systemSymbol: .exclamationmarkTriangleFill,
                )
                .foregroundStyle(.orange)
            }
            if let dashboardURL = URL(string: "https://rapidapi.com/developer/dashboard") {
                Link(String(localized: .sourceRapidAPIDashboard), destination: dashboardURL)
            }
            Text(.sourceEstimateDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
