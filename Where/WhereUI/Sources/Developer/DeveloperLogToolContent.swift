#if DEBUG
    import PeriscopeTools
    import SFSafeSymbols
    import SwiftUI
    import WhereCore

    struct DeveloperLogToolContent: View {
        let tool: DeveloperTool
        @Environment(WhereModel.self) private var model: WhereModel?

        var body: some View {
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
        }
    }

    #Preview { DeveloperOverlayPreview(presentation: .floating(.logs)) }

    /// Honest fallback when a session-scoped developer dependency disappears.
    private struct DeveloperToolUnavailableView: View {
        let tool: DeveloperTool

        var body: some View {
            ContentUnavailableView(
                String(localized: .developerUnavailableTitle),
                systemSymbol: tool.systemSymbol,
                description: Text(String(localized: .developerUnavailableDescription)),
            )
            .navigationTitle(tool.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    #Preview {
        NavigationStack {
            DeveloperToolUnavailableView(tool: .logs)
        }
    }
#endif
