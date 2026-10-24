import SwiftUI

struct Flightradar24CadenceSection: View {
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
            LabeledContent(String(localized: .sourceRequestsPerHour)) {
                Text(model.requestsPerHour, format: .number)
            }
            Flightradar24UsageContent(model: model)
            Text(.sourceFr24Pricing)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(.sourceFr24UsageGuidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://fr24api.flightradar24.com") {
                Link(String(localized: .sourceFr24Dashboard), destination: url)
            }
        }
    }
}
