#if DEBUG
    import LogViewerUI
    import RegionKit
    import SwiftDataInspector
    import SwiftUI
    import WhereCore

    /// The developer tools surface — the in-app log viewer over both process
    /// buffers (`WhereLog` for the app/WhereCore facade and `RegionLog` for
    /// RegionKit, merged chronologically), the generic SwiftData inspector (only
    /// when the live session can vend a container — previews and non-SwiftData
    /// fakes don't show it), and the region map.
    ///
    /// Owns its own `NavigationStack` so the generic viewers (which expect an
    /// ambient stack) work wherever it's hosted. It reads `WhereSession` as an
    /// *optional* because the developer overlay is reachable before login — the
    /// inspector row simply hides until a live session exists.
    ///
    /// Compiled out of release entirely (`#if DEBUG`).
    struct DeveloperToolsView: View {
        @Environment(WhereSession.self) private var session: WhereSession?

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        NavigationLink {
                            LogViewer(configuration: LogViewerConfiguration(
                                stores: [WhereLog.store, RegionLog.store],
                                title: Strings.developerLogsTitle,
                            ))
                        } label: {
                            Label(Strings.developerLogsLink, systemImage: "ladybug")
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
                    } footer: {
                        Text(Strings.developerFooter)
                    }
                }
                .navigationTitle(Strings.developerTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    #Preview {
        DeveloperToolsView()
            .environment(PreviewSupport.loadedSession())
    }
#endif
