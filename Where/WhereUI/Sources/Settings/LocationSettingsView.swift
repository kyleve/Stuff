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
                        Label(
                            String(localized: .settingsLocationToggle),
                            systemImage: "location.fill",
                        )
                    }
                    .settingsRow(Item.tracking)

                    if showGrantButton {
                        Button {
                            Task { await session.requestPermission() }
                        } label: {
                            Label(
                                String(localized: .settingsLocationGrant),
                                systemImage: "location.magnifyingglass",
                            )
                        }
                    }

                    if showOpenSettingsButton {
                        Button {
                            openSystemSettings(openURL)
                        } label: {
                            Label(
                                String(localized: .settingsPermissionAlertOpenSettings),
                                systemImage: "gear",
                            )
                        }
                    }
                } header: {
                    Text(String(localized: .settingsLocationHeader))
                } footer: {
                    Text(String(localized: .settingsLocationFooter))
                }
            }
        }
        .navigationTitle(String(localized: .settingsLocationHeader))
        .navigationBarTitleDisplayMode(.inline)
        // `session.permissionDenied` is only ever raised by the Grant button /
        // tracking toggle on this screen (an external Settings-app toggle flows
        // through the authorization observer, which never sets it), so the alert
        // belongs here rather than on the always-mounted settings root.
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
                case .tracking: String(localized: .settingsLocationToggle)
            }
        }

        var keywords: [String] {
            switch self {
                case .tracking: splitKeywords(String(localized: .settingsKeywordsTracking))
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

#if DEBUG
    extension LocationSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            LocationSettingsView.self,
            title: "Location Settings",
        ) { _ in
            LocationSettingsView()
        }
    }
#endif
