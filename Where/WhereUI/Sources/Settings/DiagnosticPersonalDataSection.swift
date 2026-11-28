#if DEBUG
    import SwiftUI

    struct DiagnosticPersonalDataSection: View {
        @Bindable var confirmation: DiagnosticPersonalDataConfirmation

        var body: some View {
            Section {
                Toggle(
                    String(localized: .settingsDiagnosticsFullMetadata),
                    isOn: $confirmation.includesPersonalData,
                )
                .settingsRow(PrivacyDiagnosticsSettingsView.Item.fullMetadata)
                .confirmationDialog(
                    String(localized: .settingsDiagnosticsFullMetadataConfirmTitle),
                    isPresented: $confirmation.isPresented,
                    titleVisibility: .visible,
                    presenting: confirmation.pendingRevision,
                ) { revision in
                    Button(
                        String(localized: .settingsDiagnosticsFullMetadataEnable),
                        role: .destructive,
                    ) {
                        confirmation.confirm(revision: revision)
                    }
                    Button(String(localized: .settingsDataCancel), role: .cancel) {}
                } message: { _ in
                    Text(String(localized: .settingsDiagnosticsFullMetadataConfirmMessage))
                }
            } footer: {
                Text(String(localized: .settingsDiagnosticsFullMetadataWarning))
                    .foregroundStyle(.red)
            }
        }
    }

    #Preview {
        Form {
            DiagnosticPersonalDataSection(confirmation: .init(
                reporting: PreviewSupport.loadedModel().diagnosticReporting,
            ))
        }
        .whereBroadwayRoot()
    }
#endif
