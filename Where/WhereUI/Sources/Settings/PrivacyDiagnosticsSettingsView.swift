import SnapshotKit
import SwiftUI
import WhereCore

/// Controls the process's vendor-neutral crash, replay, and remote-log choices.
struct PrivacyDiagnosticsSettingsView: View {
    var focus: SettingsFocus?

    @Environment(WhereModel.self) private var model

    var body: some View {
        @Bindable var reporting = model.diagnosticReporting
        @Bindable var porthole = model.porthole
        SettingsFocusScope(focus: focus) {
            Form {
                PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                    configuration: reporting.effectiveConfiguration,
                ), disclosureInteraction: .staticContent)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())

                Section {
                    Toggle(
                        String(localized: .settingsDiagnosticsCrashReports),
                        isOn: $reporting.sharesCrashReports,
                    )
                    .settingsRow(Item.crashReports)
                    if reporting.crashReportsPendingNextLaunch {
                        pendingRow(isEnabled: reporting.effectiveConfiguration.sharesCrashReports)
                    }

                    Toggle(
                        String(localized: .settingsDiagnosticsSessionReplay),
                        isOn: $reporting.sharesSessionReplays,
                    )
                    .settingsRow(Item.sessionReplay)
                    if reporting.sessionReplaysPendingNextLaunch {
                        pendingRow(isEnabled: reporting.effectiveConfiguration.sharesSessionReplays)
                    }
                } footer: {
                    Text(String(localized: .settingsDiagnosticsRelaunchFooter))
                }

                Section {
                    Picker(
                        String(localized: .settingsDiagnosticsRemoteLogging),
                        selection: $reporting.selectedRemoteLevel,
                    ) {
                        Text(String(localized: .settingsDiagnosticsOff))
                            .tag(nil as RemoteLogLevel?)
                        ForEach(RemoteLogLevel.allCases, id: \.self) { level in
                            Text(level.settingsTitle).tag(level as RemoteLogLevel?)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .settingsRow(Item.remoteLogging)

                    switch reporting.applyState {
                        case .idle:
                            EmptyView()
                        case .applying:
                            LabeledContent(String(localized: .settingsDiagnosticsApplying)) {
                                ProgressView()
                            }
                        case let .failed(message):
                            VStack(alignment: .leading) {
                                Text(String(localized: .settingsDiagnosticsApplyFailed))
                                    .foregroundStyle(.secondary)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(
                                    String(localized: .settingsDiagnosticsRetry),
                                    action: reporting.retryRemoteLogging,
                                )
                            }
                    }
                } footer: {
                    Text(String(localized: .settingsDiagnosticsRemoteFooter))
                }

                Section {
                    Toggle(String(localized: .settingsPortholeEnable), isOn: $porthole.isEnabled)
                        .settingsRow(Item.porthole)
                    switch porthole.state {
                        case .disabled, .ready:
                            EmptyView()
                        case .preparing:
                            LabeledContent(String(localized: .settingsPortholePreparing)) {
                                ProgressView()
                            }
                        case let .failed(message):
                            Text(message).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(String(localized: .settingsPortholeFooter))
                }

                #if DEBUG
                    if reporting.selectedRemoteLevel != nil {
                        Section {
                            Toggle(
                                String(localized: .settingsDiagnosticsFullMetadata),
                                isOn: $reporting.includeAllMetadataToggle,
                            )
                            .settingsRow(Item.fullMetadata)
                            .confirmationDialog(
                                String(localized: .settingsDiagnosticsFullMetadataConfirmTitle),
                                isPresented: $reporting.isMetadataConfirmationPresented,
                                titleVisibility: .visible,
                            ) {
                                Button(
                                    String(localized: .settingsDiagnosticsFullMetadataEnable),
                                    role: .destructive,
                                    action: reporting.confirmAllLogMetadata,
                                )
                                Button(String(localized: .settingsDataCancel), role: .cancel) {}
                            } message: {
                                Text(
                                    String(
                                        localized: .settingsDiagnosticsFullMetadataConfirmMessage,
                                    ),
                                )
                            }
                        } footer: {
                            Text(String(localized: .settingsDiagnosticsFullMetadataWarning))
                                .foregroundStyle(.red)
                        }
                    }
                #endif
            }
        }
        .navigationTitle(String(localized: .settingsDiagnosticsTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pendingRow(isEnabled: Bool) -> some View {
        LabeledContent(String(localized: .settingsDiagnosticsCurrentState)) {
            Text(isEnabled ? String(localized: .settingsDiagnosticsOn) :
                String(localized: .settingsDiagnosticsOff))
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
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
        case porthole
        #if DEBUG
            case fullMetadata
        #endif

        var title: String {
            switch self {
                case .crashReports: String(localized: .settingsDiagnosticsCrashReports)
                case .sessionReplay: String(localized: .settingsDiagnosticsSessionReplay)
                case .remoteLogging: String(localized: .settingsDiagnosticsRemoteLogging)
                case .porthole: String(localized: .settingsPortholeEnable)
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
                case .porthole: ["Porthole"]
                #if DEBUG
                    case .fullMetadata:
                        splitKeywords(String(localized: .settingsDiagnosticsMetadataKeywords))
                #endif
            }
        }
    }
}

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
                        metadataPolicy: .allMetadataExcludingAttachmentData,
                    ),
                ),
            )
            diagnosticSnapshot(
                name: "PortholeEnabled",
                saved: .defaults(isDebugBuild: false),
                isPortholeEnabled: true,
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPhoneFullContent],
                    colorSchemes: [.light, .dark],
                    dynamicTypes: [.large, .accessibility5],
                ),
            )
        }

        private static func diagnosticSnapshot(
            name: String,
            saved: DiagnosticReportingConfiguration,
            effective: DiagnosticReportingConfiguration? = nil,
            isPortholeEnabled: Bool = false,
            configurations: [SnapshotConfiguration] = .fullContentPhoneLightDark,
        ) -> SnapshotCase {
            whereSnapshot(
                name: name,
                configurations: configurations,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    PrivacyDiagnosticsSettingsView()
                }
                .environment(diagnosticModel(
                    saved: saved,
                    effective: effective ?? saved,
                    isPortholeEnabled: isPortholeEnabled,
                ))
            }
        }

        private static func diagnosticModel(
            saved: DiagnosticReportingConfiguration,
            effective: DiagnosticReportingConfiguration,
            isPortholeEnabled: Bool,
        ) -> WhereModel {
            let model = PreviewSupport.loadedModel(
                savedDiagnosticReporting: saved,
                effectiveDiagnosticReporting: effective,
            )
            // This settings fixture changes the preference without activating the runtime.
            model.porthole.isEnabled = isPortholeEnabled
            return model
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
