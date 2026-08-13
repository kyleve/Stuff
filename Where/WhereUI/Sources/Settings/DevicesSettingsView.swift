import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Synced device-management screen. Only the current row edits local recording preference;
/// remote rows expose advisory status and irreversible removal.
struct DevicesSettingsView: View {
    var focus: SettingsFocus?

    @Environment(WhereSession.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var model: DevicesSettingsModel
    private let loadsLiveData: Bool

    init(session: WhereSession, focus: SettingsFocus? = nil) {
        self.focus = focus
        _model = State(initialValue: DevicesSettingsModel(session: session))
        loadsLiveData = true
    }

    #if DEBUG
        init(
            session: WhereSession,
            configurations: [RecordingDeviceConfiguration],
            focus: SettingsFocus? = nil,
        ) {
            self.focus = focus
            _model = State(
                initialValue: DevicesSettingsModel(
                    session: session,
                    configurations: configurations,
                ),
            )
            loadsLiveData = false
        }
    #endif

    var body: some View {
        @Bindable var session = session
        @Bindable var model = model
        SettingsFocusScope(
            focus: focus,
            revealWhen: model.state.isReadyForSearchFocus,
        ) {
            Form {
                switch model.state {
                    case .idle, .loading:
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    case let .failed(failure):
                        Section {
                            ContentUnavailableView(
                                String(localized: .settingsDevicesLoadFailed),
                                systemSymbol: .exclamationmarkIcloud,
                                description: Text(failure.message),
                            )
                            Button(String(localized: .commonRetry)) {
                                Task { await model.retry() }
                            }
                        }
                    case .empty:
                        Section {
                            ContentUnavailableView(
                                String(localized: .settingsDevicesLoadFailed),
                                systemSymbol: .exclamationmarkIcloud,
                            )
                            Button(String(localized: .commonRetry)) {
                                Task { await model.retry() }
                            }
                        }
                    case .loaded:
                        ForEach(model.rows) { row in
                            DeviceSettingsSection(model: model, row: row)
                        }
                }
            }
        }
        .navigationTitle(String(localized: .settingsDevicesTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard loadsLiveData else { return }
            await model.run()
        }
        .alert(
            String(localized: .settingsDevicesErrorTitle),
            isPresented: $model.isShowingError,
            presenting: model.presentedFailure,
        ) { _ in
            if model.presentedFailureCanRetry {
                Button(String(localized: .commonRetry)) {
                    Task { await model.retry() }
                }
            }
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .alert(
            String(localized: .settingsPermissionAlertTitle),
            isPresented: $session.permissionDenied,
        ) {
            Button(String(localized: .settingsPermissionAlertOpenSettings)) {
                openSystemSettings(openURL)
            }
            Button(String(localized: .settingsPermissionAlertNotNow), role: .cancel) {}
        } message: {
            Text(String(localized: .settingsPermissionAlertMessage))
        }
    }
}

extension DevicesSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .devices
    }

    enum Item: SettingsItem {
        case automaticRecording
        case deviceName

        var title: String {
            switch self {
                case .automaticRecording:
                    String(localized: .settingsDevicesAutomaticRecording)
                case .deviceName:
                    String(localized: .settingsDevicesName)
            }
        }

        var keywords: [String] {
            switch self {
                case .automaticRecording:
                    splitKeywords(String(localized: .settingsDevicesKeywordsRecording))
                case .deviceName:
                    splitKeywords(String(localized: .settingsDevicesKeywordsName))
            }
        }
    }
}

#if DEBUG
    extension DevicesSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let session = PreviewSupport.loadedSession()
            let permissionRequiredSession = PreviewSupport.whenInUseSession()
            whereSnapshot(
                name: "Default",
                configurations: .screenDefaults,
                onReadyToSnapshot: { await session.start() },
            ) {
                NavigationStack {
                    DevicesSettingsView(
                        session: session,
                        configurations: PreviewSupport.recordingDeviceConfigurations(),
                    )
                }
                .environment(session)
                .task { await session.start() }
            }
            whereSnapshot(
                name: "PermissionRequiredRecordingOff",
                configurations: .fullContentPhoneLightDark,
                onReadyToSnapshot: { await permissionRequiredSession.start() },
            ) {
                NavigationStack {
                    DevicesSettingsView(
                        session: permissionRequiredSession,
                        configurations: PreviewSupport.recordingDeviceConfigurations(
                            automaticRecordingEnabled: false,
                        ),
                    )
                }
                .environment(permissionRequiredSession)
                .task { await permissionRequiredSession.start() }
            }
        }
    }

    #Preview {
        DevicesSettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension DevicesSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            DevicesSettingsView.self,
            title: "Devices",
        ) { world in
            DevicesSettingsView(
                session: world.session,
                configurations: PreviewSupport.recordingDeviceConfigurations(),
            )
        }
    }
#endif
