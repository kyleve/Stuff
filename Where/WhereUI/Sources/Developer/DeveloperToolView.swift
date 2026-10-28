import SFSafeSymbols
#if DEBUG
    import PeriscopeTools
    import SwiftUI
    import WhereCore

    /// Hosts one selected developer tool as the root of its own navigation stack.
    ///
    /// The lightweight accordion owns routing; this surface owns only the ambient
    /// stack each tool expects. Making the selected tool the stack root removes
    /// the redundant Developer list title/back button while preserving every
    /// tool's own drill-ins and toolbar.
    ///
    /// The optional dependencies can disappear if the app resets while a tool is
    /// open. That renders an honest unavailable state rather than retaining stale
    /// session resources or crashing.
    struct DeveloperToolView: View {
        let tool: DeveloperTool

        @Environment(WhereModel.self) private var model: WhereModel?

        var body: some View {
            NavigationStack {
                switch tool {
                    case .crashTesting:
                        DeveloperCrashTestingView()

                    case .logs:
                        switch model?.logStoreState {
                            case let .ready(store):
                                PeriscopeViewer(
                                    store: store,
                                    title: String(localized: .developerLogsTitle),
                                )

                            case .opening:
                                ContentUnavailableView(
                                    String(localized: .developerLoggingOpeningTitle),
                                    systemSymbol: tool.systemSymbol,
                                    description: Text(String(
                                        localized: .developerLoggingOpeningDescription,
                                    )),
                                )
                                .navigationTitle(tool.title)
                                .navigationBarTitleDisplayMode(.inline)

                            case let .failed(description):
                                ContentUnavailableView(
                                    String(localized: .developerLoggingFailedTitle),
                                    systemSymbol: .exclamationmarkTriangle,
                                    description: Text(description),
                                )
                                .navigationTitle(tool.title)
                                .navigationBarTitleDisplayMode(.inline)

                            case .unavailable, nil:
                                DeveloperToolUnavailableView(tool: tool)
                        }

                    case .openSpans:
                        OpenSpansView(system: .shared)

                    case .regionMap:
                        RegionMapView()
                }
            }
        }
    }

    #Preview("Region map") {
        DeveloperToolView(tool: .regionMap)
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
    }

    #Preview("Crash testing") {
        DeveloperToolView(tool: .crashTesting)
    }
#endif
