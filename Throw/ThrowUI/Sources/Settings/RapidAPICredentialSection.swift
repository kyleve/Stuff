import SFSafeSymbols
import SwiftUI

struct RapidAPICredentialSection: View {
    @Bindable var model: AircraftSourceSettingsModel

    var body: some View {
        Section {
            Text(.sourceDedicatedKeyGuidance)
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
                        if let lastFour {
                            Text(verbatim: "•••• \(lastFour)")
                                .privacySensitive()
                        } else {
                            Text(.statusConnected)
                        }
                    }
            }

            if model.isEditingCredential {
                SecureField(String(localized: .sourceCredential), text: $model.rapidAPIKey)
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
            if let subscriptionURL =
                URL(string: "https://www.adsbexchange.com/community/developer-hub/")
            {
                Link(String(localized: .sourceSubscribe), destination: subscriptionURL)
            }
            Text(.sourceTestConsumesRequest)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if case .saved = model.credentialState {
                Button(String(localized: .commonDelete), role: .destructive) {
                    Task(name: "Throw delete RapidAPI credential") {
                        await model.deleteCredential()
                    }
                }
            }
        } header: {
            Text(.sourceCredential)
        }
    }
}
