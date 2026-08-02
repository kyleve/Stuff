#if DEBUG
    import Foundation
    import Inspector
    import PeriscopeTools
    import SwiftUI
    import WhereCore

    /// Async preview host that supplies the same app-level developer dependencies
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
                        .environment(context.modeController as InspectorModeController?)
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
                    modeController: makeModeController(),
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

        private func makeModeController() -> InspectorModeController {
            let suiteName = "where.developer-overlay.preview.inspector"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open Inspector preview defaults")
            }
            defaults.removePersistentDomain(forName: suiteName)
            return InspectorModeController(userDefaults: defaults)
        }
    }

    #Preview("Menu") {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
