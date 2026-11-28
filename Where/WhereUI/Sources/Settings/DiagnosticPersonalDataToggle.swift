#if DEBUG
    import SwiftUI

    struct DiagnosticPersonalDataToggle: View {
        @Bindable var confirmation: DiagnosticPersonalDataConfirmation

        var body: some View {
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
        }
    }

    #Preview {
        Form {
            DiagnosticPersonalDataToggle(confirmation: .init(reporting: PreviewSupport.loadedModel()
                    .diagnosticReporting))
        }.whereBroadwayRoot()
    }
#endif
