import SnapshotKit
import SwiftUI
import WhereCore

/// Controls the process's vendor-neutral crash, replay, and remote-log choices.
struct PrivacyDiagnosticsSettingsView: View {
    var focus: SettingsFocus?

    @Environment(WhereModel.self) private var model

    var body: some View {
        let reporting = model.diagnosticReporting
        SettingsFocusScope(focus: focus) {
            Form {
                PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                    configuration: reporting.effectiveConfiguration,
                ), disclosureInteraction: .staticContent)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())

                DiagnosticCaptureSection(reporting: reporting)

                DiagnosticRemoteLoggingSection(reporting: reporting)

                #if DEBUG
                    if reporting.selectedRemoteLevel != nil {
                        DiagnosticPersonalDataControls(reporting: reporting)
                    }
                #endif
            }
            .whereFormRoot()
        }
        .navigationTitle(String(localized: .settingsDiagnosticsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension PrivacyDiagnosticsSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .privacyDiagnostics
    }

    enum Item: SettingsItem {
        case crashReports
        case sessionReplay
        case remoteLogging
        #if DEBUG
            case fullMetadata
        #endif

        var title: String {
            switch self {
                case .crashReports: String(localized: .settingsDiagnosticsCrashReports)
                case .sessionReplay: String(localized: .settingsDiagnosticsSessionReplay)
                case .remoteLogging: String(localized: .settingsDiagnosticsRemoteLogging)
                #if DEBUG
                    case .fullMetadata: String(localized: .settingsDiagnosticsFullMetadata)
                #endif
            }
        }

        var keywords: [String] {
            switch self {
                case .crashReports:
                    splitKeywords(String(localized: .settingsDiagnosticsCrashKeywords))
                case .sessionReplay:
                    splitKeywords(String(localized: .settingsDiagnosticsReplayKeywords))
                case .remoteLogging:
                    splitKeywords(String(localized: .settingsDiagnosticsLoggingKeywords))
                #if DEBUG
                    case .fullMetadata:
                        splitKeywords(String(localized: .settingsDiagnosticsMetadataKeywords))
                #endif
            }
        }
    }
}

private struct DiagnosticPendingRow: View {
    let isEnabled: Bool

    var body: some View {
        LabeledContent(String(localized: .settingsDiagnosticsCurrentState)) {
            Text(isEnabled ? String(localized: .settingsDiagnosticsOn) :
                String(localized: .settingsDiagnosticsOff))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct DiagnosticCaptureSection: View {
    @Bindable var reporting: DiagnosticReportingSettingsModel

    var body: some View {
        Section {
            DiagnosticCaptureToggle(item: .crashReports, isOn: $reporting.sharesCrashReports)
            if reporting.crashReportsPendingNextLaunch {
                DiagnosticPendingRow(isEnabled: reporting.effectiveConfiguration.sharesCrashReports)
            }

            DiagnosticCaptureToggle(item: .sessionReplay, isOn: $reporting.sharesSessionReplays)
            if reporting.sessionReplaysPendingNextLaunch {
                DiagnosticPendingRow(isEnabled: reporting.effectiveConfiguration
                    .sharesSessionReplays)
            }
        } footer: {
            Text(String(localized: .settingsDiagnosticsRelaunchFooter))
        }
    }
}

private struct RemoteLogLevelPicker: View {
    @Binding var selectedLevel: RemoteLogLevel?

    var body: some View {
        Picker(
            String(localized: .settingsDiagnosticsRemoteLogging),
            selection: $selectedLevel,
        ) {
            Text(String(localized: .settingsDiagnosticsOff))
                .tag(nil as RemoteLogLevel?)
            ForEach(RemoteLogLevel.allCases, id: \.self) { level in
                Text(level.settingsTitle).tag(level as RemoteLogLevel?)
            }
        }
        .pickerStyle(.navigationLink)
        .settingsRow(PrivacyDiagnosticsSettingsView.Item.remoteLogging)
    }
}

private struct DiagnosticApplyFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: .settingsDiagnosticsApplyFailed))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(
                String(localized: .settingsDiagnosticsRetry),
                action: retry,
            )
        }
    }
}

private struct DiagnosticApplyStatus: View {
    let state: DiagnosticReportingSettingsModel.ApplyState
    let retry: () -> Void

    var body: some View {
        switch state {
            case .idle:
                EmptyView()
            case .applying:
                LabeledContent(String(localized: .settingsDiagnosticsApplying)) {
                    ProgressView()
                }
            case let .failed(message):
                DiagnosticApplyFailure(message: message, retry: retry)
        }
    }
}

private struct DiagnosticRemoteLoggingSection: View {
    @Bindable var reporting: DiagnosticReportingSettingsModel

    var body: some View {
        Section {
            RemoteLogLevelPicker(selectedLevel: $reporting.selectedRemoteLevel)

            DiagnosticApplyStatus(state: reporting.applyState, retry: reporting.retryRemoteLogging)
        } footer: {
            Text(String(localized: .settingsDiagnosticsRemoteFooter))
        }
    }
}

private struct DiagnosticCaptureToggle: View {
    let item: PrivacyDiagnosticsSettingsView.Item
    @Binding var isOn: Bool

    var body: some View {
        Toggle(item.title, isOn: $isOn)
            .settingsRow(item)
    }
}

#if DEBUG
    private struct DiagnosticPersonalDataControls: View {
        let reporting: DiagnosticReportingSettingsModel

        var body: some View {
            ObservableHostingView {
                DiagnosticPersonalDataConfirmation(reporting: reporting)
            } content: { confirmation in
                DiagnosticPersonalDataSection(confirmation: confirmation)
            }
        }
    }
#endif

extension RemoteLogLevel {
    fileprivate var settingsTitle: String {
        switch self {
            case .fault: String(localized: .settingsDiagnosticsLevelFault)
            case .error: String(localized: .settingsDiagnosticsLevelError)
            case .warning: String(localized: .settingsDiagnosticsLevelWarning)
            case .notice: String(localized: .settingsDiagnosticsLevelNotice)
            case .info: String(localized: .settingsDiagnosticsLevelInfo)
            case .debug: String(localized: .settingsDiagnosticsLevelDebug)
        }
    }
}

#if DEBUG
    extension PrivacyDiagnosticsSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            diagnosticSnapshot(
                name: "AllOff",
                saved: DiagnosticReportingConfiguration(
                    sharesCrashReports: false,
                    sharesSessionReplays: false,
                    remoteLogging: .off,
                ),
            )
            diagnosticSnapshot(
                name: "ShippingDefault",
                saved: .defaults(isDebugBuild: false),
            )
            diagnosticSnapshot(
                name: "DebugDefault",
                saved: .defaults(isDebugBuild: true),
            )
            diagnosticSnapshot(
                name: "PendingRelaunch",
                saved: DiagnosticReportingConfiguration(
                    sharesCrashReports: false,
                    sharesSessionReplays: true,
                    remoteLogging: .off,
                ),
                effective: .defaults(isDebugBuild: false),
            )
            diagnosticSnapshot(
                name: "FullMetadataWarning",
                saved: DiagnosticReportingConfiguration(
                    sharesCrashReports: true,
                    sharesSessionReplays: false,
                    remoteLogging: .enabled(
                        minimumLevel: .warning,
                        exportPolicy: .init(
                            mode: .diagnostic,
                            enabledControls: RemoteLoggingConfiguration.personalDataControls,
                        ),
                    ),
                ),
            )
        }

        private static func diagnosticSnapshot(
            name: String,
            saved: DiagnosticReportingConfiguration,
            effective: DiagnosticReportingConfiguration? = nil,
        ) -> SnapshotCase {
            whereSnapshot(
                name: name,
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                PrivacyDiagnosticsSnapshot(saved: saved, effective: effective ?? saved)
            }
        }
    }

    private struct PrivacyDiagnosticsSnapshot: View {
        let saved: DiagnosticReportingConfiguration
        let effective: DiagnosticReportingConfiguration

        var body: some View {
            NavigationStack {
                PrivacyDiagnosticsSettingsView()
            }
            .environment(PreviewSupport.loadedModel(
                savedDiagnosticReporting: saved,
                effectiveDiagnosticReporting: effective,
            ))
        }
    }

    #Preview {
        PrivacyDiagnosticsSettingsView.snapshotPreviews
    }

    extension PrivacyDiagnosticsSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PrivacyDiagnosticsSettingsView.self,
            title: "Privacy & Diagnostics",
        )
    }
#endif

#if DEBUG
    private struct DiagnosticPersonalDataSection: View {
        let confirmation: DiagnosticPersonalDataConfirmation

        var body: some View {
            Section {
                DiagnosticPersonalDataToggle(confirmation: confirmation)
            } footer: {
                Text(String(localized: .settingsDiagnosticsFullMetadataWarning))
                    .foregroundStyle(.red)
            }
        }
    }

    #Preview("Personal data") { DiagnosticPersonalDataPreview() }

    private struct DiagnosticPersonalDataPreview: View {
        var body: some View {
            Form {
                DiagnosticPersonalDataSection(confirmation: .init(
                    reporting: PreviewSupport.loadedModel().diagnosticReporting,
                ))
            }
            .whereBroadwayRoot()
        }
    }
#endif
