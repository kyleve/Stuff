import SFSafeSymbols
import SwiftUI

struct Flightradar24CredentialSection: View {
    @Bindable var model: AircraftSourceSettingsModel

    var body: some View {
        Section {
            Text(.sourceFr24CredentialGuidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch model.credentialState {
                case .missing:
                    Label(
                        String(localized: .sourceCredentialMissing),
                        systemSymbol: .exclamationmarkTriangleFill,
                    )
                    .foregroundStyle(.red)
                case let .saved(lastFour):
                    LabeledContent(String(localized: .sourceCredentialSaved)) {
                        Text(
                            verbatim: lastFour.map { "•••• \($0)" } ??
                                String(localized: .statusConnected),
                        )
                        .privacySensitive()
                    }
            }

            if model.isEditingCredential {
                SecureField(String(localized: .sourceFr24Credential), text: $model.rapidAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if case .saved = model.credentialState {
                    Button(
                        String(localized: .commonCancel),
                        action: model.cancelCredentialReplacement,
                    )
                }
            } else {
                Button(String(localized: .commonReplace), systemSymbol: .arrowClockwise) {
                    model.replaceCredential()
                }
            }
            if let url =
                URL(string: "https://fr24api.flightradar24.com/subscriptions-and-credits")
            {
                Link(String(localized: .sourceSubscribe), destination: url)
            }
            Text(.sourceFr24TestConsumesCredits)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if case .saved = model.credentialState {
                Button(String(localized: .commonDelete), role: .destructive) {
                    Task(name: "Throw delete Flightradar24 credential") {
                        await model.deleteCredential()
                    }
                }
            }
        } header: {
            Text(.sourceFr24Credential)
        }
    }
}
