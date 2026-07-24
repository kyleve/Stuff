#if DEBUG
    import PeriscopeCore
    import PortholeKit
    import PortholeKitUI
    import PortholePeriscope
    import PortholeSwiftData
    import SwiftUI
    import WhereCore
    import WherePorthole

    /// The DEBUG-only Porthole developer surface: lazily builds a `Porthole` with
    /// the Where connectors registered (plus the built-ins) and shows the pairing
    /// UI. Compiled out of release entirely.
    struct PortholeDeveloperView: View {
        @Environment(WhereModel.self) private var model: WhereModel?
        @Environment(WhereSession.self) private var session: WhereSession?
        @State private var porthole: Porthole?

        var body: some View {
            Group {
                if let porthole {
                    PortholePairingView(porthole: porthole)
                } else {
                    ProgressView()
                        .task { porthole = makePorthole() }
                }
            }
        }

        @MainActor
        private func makePorthole() -> Porthole? {
            guard let session else { return nil }
            let porthole = Porthole(configuration: PortholeConfiguration(
                appName: "Where",
                appGroupIdentifiers: ["group.com.stuff.where"],
            ))
            porthole.register(WhereConnector(
                services: session.services,
                preferences: WherePreferencesSnapshot(
                    hasOnboarded: session.preferences.hasOnboarded,
                    wantsTracking: session.preferences.wantsTracking,
                    remindersEnabled: session.preferences.remindersEnabled,
                    summaryEnabled: session.preferences.summaryEnabled,
                    issueAlertsEnabled: session.preferences.issueAlertsEnabled,
                    driftThresholdMeters: session.preferences.driftThresholdMeters,
                ),
            ))
            if let store = model?.logStore {
                porthole.register(PeriscopeConnector(store: store, system: .shared))
            }
            if let container = session.services.modelContainer {
                porthole.register(SwiftDataConnector(
                    id: "swiftdata",
                    title: "SwiftData",
                    container: container,
                    modelTypes: SwiftDataStore.inspectorModelTypes,
                    rowLimit: 500,
                ))
            }
            return porthole
        }
    }
#endif
