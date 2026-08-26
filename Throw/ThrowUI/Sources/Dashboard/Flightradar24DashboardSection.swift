import SFSafeSymbols
import SwiftUI
import ThrowCore

struct Flightradar24DashboardSection: View {
    let credentialState: CredentialState
    let intervalSeconds: Int
    let requestsPerHour: Int

    var body: some View {
        Section {
            switch credentialState {
                case .missing:
                    Label(
                        String(localized: .sourceCredentialMissing),
                        systemSymbol: .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(.red)
                case let .saved(lastFour):
                    LabeledContent(String(localized: .sourceCredentialSaved)) {
                        Text(verbatim: lastFour.map { "•••• \($0)" } ?? "Saved")
                            .privacySensitive()
                    }
            }
            LabeledContent(String(localized: .sourceInterval)) {
                Text(
                    Duration.seconds(intervalSeconds),
                    format: .time(pattern: .minuteSecond),
                )
            }
            LabeledContent(String(localized: .sourceRequestsPerHour)) {
                Text(requestsPerHour, format: .number)
            }
            Text(.sourceFr24Pricing)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let url = URL(string: "https://fr24api.flightradar24.com") {
                Link(String(localized: .sourceFr24Dashboard), destination: url)
            }
        } header: {
            Text(.sourceFlightradar24)
        }
    }
}
