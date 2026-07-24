#if DEBUG
    import PeriscopeCore
    import PeriscopeTools
    import SwiftDataInspector
    import SwiftUI
    import WhereCore

    /// The developer tools surface — the Periscope log viewer + open-spans
    /// monitor, the "Log View Mode" toggle, the generic SwiftData inspector (only
    /// when the live session can vend a container), and the region map.
    ///
    /// Owns its own `NavigationStack` so the generic viewers (which expect an
    /// ambient stack) work wherever it's hosted. It reads the app `WhereModel`
    /// (for the process-global log store) and the `WhereSession` as *optionals*
    /// because the developer overlay is reachable before login and in fixtures
    /// that inject only one of them — the dependent rows just hide until their
    /// source exists.
    ///
    /// Compiled out of release entirely (`#if DEBUG`).
    struct DeveloperToolsView: View {
        @Environment(WhereModel.self) private var model: WhereModel?
        @Environment(WhereSession.self) private var session: WhereSession?
        @Environment(\.periscopeInspector) private var inspector

        /// Extra bottom scroll inset so the last rows clear the floating HUD's
        /// resize grip. Zero (the default) when hosted without the overlay chrome
        /// (previews, tests, full screen).
        var bottomContentInset: CGFloat = 0

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        if let store = model?.logStore {
                            NavigationLink {
                                PeriscopeViewer(store: store, title: Strings.developerLogsTitle)
                            } label: {
                                Label(Strings.developerLogsLink, systemImage: "ladybug")
                            }
                        }

                        NavigationLink {
                            OpenSpansView(system: .shared)
                        } label: {
                            Label(Strings.developerOpenSpansLink, systemImage: "timer")
                        }

                        if let configuration = session?.swiftDataInspectorConfiguration {
                            NavigationLink {
                                SwiftDataInspectorView(configuration: configuration)
                            } label: {
                                Label(
                                    Strings.developerInspectorLink,
                                    systemImage: "cylinder.split.1x2",
                                )
                            }
                        }

                        NavigationLink {
                            RegionMapView()
                        } label: {
                            Label(Strings.developerRegionMapLink, systemImage: "map")
                        }

                        NavigationLink {
                            PortholeDeveloperView()
                        } label: {
                            Label(
                                Strings.developerPortholeLink,
                                systemImage: "point.3.connected.trianglepath.dotted",
                            )
                        }
                    } footer: {
                        Text(Strings.developerFooter)
                    }

                    if let inspector {
                        LogViewModeSection(inspector: inspector)
                    }
                }
                .navigationTitle(Strings.developerTitle)
                .navigationBarTitleDisplayMode(.inline)
                // Let the HUD's glass surface show through the list.
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, bottomContentInset, for: .scrollContent)
            }
        }
    }

    /// The "Log View Mode" toggle: binds straight to the injected
    /// ``PeriscopeInspector`` (the source of truth is `Periscope.shared`'s
    /// inspect flag, which the inspector mirrors both ways), so flipping it
    /// reveals the inspect badges `debugLogInspectable(_:)` adds across the app.
    private struct LogViewModeSection: View {
        @Bindable var inspector: PeriscopeInspector

        var body: some View {
            Section {
                Toggle(Strings.developerLogViewMode, isOn: $inspector.isEnabled)
            } footer: {
                Text(Strings.developerLogViewModeFooter)
            }
        }
    }

    #Preview {
        DeveloperToolsView()
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }
#endif
