import SwiftUI
import WhereCore

/// Settings drill-in for location permission and background tracking: the live
/// status row, the tracking toggle, and the grant / open-Settings affordances
/// that depend on the current authorization.
struct LocationSettingsView: View {
    var focus: SettingsFocus?

    @Environment(WhereSession.self) private var session
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var session = session
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    LocationStatusRow(
                        status: session.authorizationStatus,
                        isTracking: session.isTracking,
                    )

                    Toggle(isOn: $session.trackingEnabled) {
                        Label(Strings.settingsLocationToggle, systemImage: "location.fill")
                    }
                    .settingsRow(Item.tracking)

                    if showGrantButton {
                        Button {
                            Task { await session.requestPermission() }
                        } label: {
                            Label(
                                Strings.settingsLocationGrant,
                                systemImage: "location.magnifyingglass",
                            )
                        }
                    }

                    if showOpenSettingsButton {
                        Button {
                            openSystemSettings(openURL)
                        } label: {
                            Label(Strings.settingsPermissionAlertOpenSettings, systemImage: "gear")
                        }
                    }
                } header: {
                    Text(Strings.settingsLocationHeader)
                } footer: {
                    Text(Strings.settingsLocationFooter)
                }
            }
        }
        .navigationTitle(Strings.settingsLocationHeader)
        .navigationBarTitleDisplayMode(.inline)
        // `session.permissionDenied` is only ever raised by the Grant button /
        // tracking toggle on this screen (an external Settings-app toggle flows
        // through the authorization observer, which never sets it), so the alert
        // belongs here rather than on the always-mounted settings root.
        .alert(Strings.settingsPermissionAlertTitle, isPresented: $session.permissionDenied) {
            Button(Strings.settingsPermissionAlertOpenSettings) { openSystemSettings(openURL) }
            Button(Strings.settingsPermissionAlertNotNow, role: .cancel) {}
        } message: {
            Text(Strings.settingsPermissionAlertMessage)
        }
    }

    /// Re-requesting only helps before the user has made a final decision.
    private var showGrantButton: Bool {
        switch session.authorizationStatus {
            case .notDetermined, .whenInUse: true
            case .restricted, .denied, .always: false
        }
    }

    /// Once access is denied/restricted (or stuck at When-In-Use), the only way
    /// forward is the Settings app.
    private var showOpenSettingsButton: Bool {
        switch session.authorizationStatus {
            case .denied, .restricted, .whenInUse: true
            case .notDetermined, .always: false
        }
    }
}

extension LocationSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .location
    }

    enum Item: SettingsItem {
        case tracking

        var title: String {
            switch self {
                case .tracking: Strings.settingsLocationToggle
            }
        }

        var keywords: [String] {
            switch self {
                case .tracking: splitKeywords(Strings.settingsKeywordsTracking)
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            LocationSettingsView()
                .environment(PreviewSupport.loadedSession())
        }
        .whereBroadwayRoot()
    }
#endif
