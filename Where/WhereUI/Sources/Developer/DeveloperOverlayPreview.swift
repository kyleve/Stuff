#if DEBUG
    import PeriscopeTools
    import SwiftUI
    import WhereCore

    /// Async preview host that supplies the same attached log/session dependencies
    /// as the running app without touching disk.
    struct DeveloperOverlayPreview: View {
        let presentation: DeveloperOverlayModel.Presentation
        var corner: DeveloperOverlayModel.Corner = .bottomTrailing

        @State private var context: DeveloperOverlayPreviewContext?

        var body: some View {
            Group {
                if let context {
                    DeveloperOverlay(model: context.overlayModel)
                        .environment(context.model)
                        .environment(context.session)
                        .environment(\.periscopeInspector, context.inspector)
                } else {
                    ProgressView()
                }
            }
            .task { await load() }
        }

        private func load() async {
            guard context == nil else { return }
            do {
                let store = try await PreviewSupport.previewLogStore()
                let model = PreviewSupport.loadedModel(withLogStore: store)
                context = DeveloperOverlayPreviewContext(
                    model: model,
                    session: PreviewSupport.loadedSession(),
                    inspector: PeriscopeInspector(system: .shared, store: store),
                    overlayModel: DeveloperOverlayModel(
                        store: InMemoryKeyValueStore(),
                        initialPresentation: presentation,
                        initialCorner: corner,
                    ),
                )
            } catch {
                preconditionFailure("Could not build developer overlay preview: \(error)")
            }
        }
    }

    #Preview("Menu") {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
