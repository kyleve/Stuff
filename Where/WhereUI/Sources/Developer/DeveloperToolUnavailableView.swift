#if DEBUG
    import SwiftUI

    /// Honest fallback when a session-scoped developer dependency disappears.
    struct DeveloperToolUnavailableView: View {
        let tool: DeveloperTool

        var body: some View {
            ContentUnavailableView(
                String(localized: .developerUnavailableTitle),
                systemImage: tool.systemImage,
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
