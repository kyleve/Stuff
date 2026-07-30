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
                    case .logs:
                        if let store = model?.logStore {
                            PeriscopeViewer(
                                store: store,
                                title: String(localized: .developerLogsTitle),
                            )
                        } else {
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
#endif
