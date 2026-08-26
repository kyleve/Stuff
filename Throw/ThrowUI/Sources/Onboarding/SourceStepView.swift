import SFSafeSymbols
import SwiftUI

struct SourceStepView: View {
    @Bindable var model: OnboardingFlowModel

    var body: some View {
        Form {
            Section {
                ForEach(AircraftSourceChoice.allCases, id: \.self) { source in
                    Button {
                        model.sourceChoice = source
                        model.sourceValidation = .untested
                    } label: {
                        SourceChoiceLabel(source: source, selected: model.sourceChoice == source)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(.onboardingSourceTitle)
            } footer: {
                Text(.onboardingSourceDescription)
            }

            if model.sourceChoice == .readsb {
                Section {
                    TextField(String(localized: .sourceLocalURL), text: $model.readsbURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
            }

            if model.sourceChoice == .adsbExchange {
                Section {
                    Text(.sourceDedicatedKeyGuidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let subscriptionURL =
                        URL(string: "https://www.adsbexchange.com/community/developer-hub/")
                    {
                        Link(String(localized: .sourceSubscribe), destination: subscriptionURL)
                    }
                    credentialState
                    SecureField(String(localized: .sourceCredential), text: $model.rapidAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(.sourceTestConsumesRequest)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent(String(localized: .sourceInterval)) {
                        Text(
                            Duration.seconds(Int(model.pollingIntervalSeconds)),
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
                } header: {
                    Text(.sourceCredential)
                }

                Section {
                    LabeledContent(String(localized: .sourceRequestsPerHour)) {
                        Text(
                            model.usageEstimate.displayedRequestsPerHour,
                            format: .number,
                        )
                    }
                    LabeledContent(String(localized: .sourceRequests30Days)) {
                        Text(
                            model.usageEstimate.displayedThirtyDayUpperBound,
                            format: .number,
                        )
                    }
                    Text(.sourceAllowance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(.sourceUsageExamples)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.usageEstimate.exceedsPublishedAllowance {
                        Label(
                            String(localized: .sourceQuotaWarning),
                            systemSymbol: .exclamationmarkTriangleFill,
                        )
                        .foregroundStyle(.orange)
                    }
                    if let dashboardURL = URL(string: "https://rapidapi.com/developer/dashboard") {
                        Link(String(localized: .sourceRapidAPIDashboard), destination: dashboardURL)
                    }
                } footer: {
                    Text(.sourceEstimateDisclaimer)
                }
            }

            if model.sourceChoice == .flightradar24 {
                Section {
                    Text(.sourceFr24CredentialGuidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let url = URL(
                        string: "https://fr24api.flightradar24.com/subscriptions-and-credits",
                    ) {
                        Link(String(localized: .sourceSubscribe), destination: url)
                    }
                    credentialState
                    SecureField(String(localized: .sourceFr24Credential), text: $model.rapidAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(.sourceFr24TestConsumesCredits)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent(String(localized: .sourceInterval)) {
                        Text(
                            Duration.seconds(Int(model.pollingIntervalSeconds)),
                            format: .time(pattern: .minuteSecond),
                        )
                    }
                    Slider(value: $model.pollingIntervalSeconds, in: 5 ... 300, step: 1)
                        .accessibilityLabel(Text(.sourceInterval))
                    Text(.sourceFr24Pricing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(.sourceFr24UsageGuidance)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(.sourceFr24Credential)
                }
            }

            if model.sourceChoice != nil {
                Section {
                    Button(
                        String(localized: .sourceTestConnection),
                        systemSymbol: .antennaRadiowavesLeftAndRight,
                    ) {
                        Task(name: "Throw test aircraft source") {
                            await model.testSource()
                        }
                    }
                    .disabled(model.sourceValidation == .testing)
                    SourceValidationLabel(state: model.sourceValidation)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var credentialState: some View {
        switch model.rapidAPICredentialState {
            case .missing:
                if model.rapidAPIKey.isEmpty {
                    Label(
                        String(localized: .sourceCredentialMissing),
                        systemSymbol: .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(.red)
                }
            case let .saved(lastFour):
                LabeledContent(
                    String(localized: model.hasStagedRapidAPICredential
                        ? .sourceCredentialStaged
                        : .sourceCredentialSaved),
                ) {
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
