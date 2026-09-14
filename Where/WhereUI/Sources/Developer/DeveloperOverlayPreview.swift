#if DEBUG
    import Foundation
    import Inspector
    import PeriscopeTools
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// Async preview host that supplies the same app-level developer dependencies
    /// as the running app without touching disk.
    struct DeveloperOverlayPreview: View {
        enum Surface { case overlay, menuContent, logViewMode }

        static let menuContentFrame = SnapshotConfiguration.Frame.iPhoneFullContent

        let presentation: DeveloperOverlayModel.Presentation
        var corner: DeveloperOverlayModel.Corner = .bottomTrailing
        var isPortholeEnabled = false
        var surface: Surface = .overlay

        @Environment(\.stylesheet) private var stylesheet

        @State private var context: DeveloperOverlayPreviewContext?

        var body: some View {
            Group {
                if let context {
                    Group {
                        switch surface {
                            case .overlay:
                                DeveloperOverlay(model: context.overlayModel)
                            case .menuContent:
                                DeveloperOverlayMenuContent(
                                    isPresented: true,
                                    corner: corner,
                                    onOpenDestination: { _ in },
                                    onConfigureDemo: {},
                                )
                                .frame(maxWidth: stylesheet.developerOverlay.menu.maxWidth)
                                .padding(stylesheet.developerOverlay.edgeInset)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: menuContentMinimumHeight,
                                    alignment: .topLeading,
                                )
                                .background(Color(uiColor: .systemBackground))
                            case .logViewMode:
                                DeveloperLogViewModeRow(inspector: context.inspector)
                                    .frame(maxWidth: stylesheet.developerOverlay.menu.maxWidth)
                                    .padding(stylesheet.developerOverlay.edgeInset)
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity,
                                        alignment: .topLeading,
                                    )
                                    .background(Color(uiColor: .systemBackground))
                        }
                    }
                    .environment(context.model)
                    .environment(context.modeController as WhereDeveloperLaunchController?)
                    .environment(\.periscopeInspector, context.inspector)
                } else {
                    ProgressView()
                }
            }
            .task { await load() }
        }

        /// Fill the same minimum viewport that owns this fixture's snapshot matrix. The row
        /// stack keeps its natural height above that minimum, including accessibility sizes.
        private var menuContentMinimumHeight: CGFloat? {
            guard case let .fullContent(_, minimumHeight) = Self.menuContentFrame.size else {
                preconditionFailure("The shared menu fixture requires a full-content frame")
            }
            return minimumHeight
        }

        private func load() async {
            guard context == nil else { return }
            do {
                let store = try await PreviewSupport.previewLogStore()
                let model = PreviewSupport.loadedModel(withLogStore: store)
                // Set the saved choice without running the application's activation task.
                model.porthole.isEnabled = isPortholeEnabled
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

        private func makeModeController() -> WhereDeveloperLaunchController {
            let suiteName = "where.developer-overlay.preview.inspector"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open Inspector preview defaults")
            }
            defaults.removePersistentDomain(forName: suiteName)
            return WhereDeveloperLaunchController(
                userDefaults: defaults,
                inspectorModeController: InspectorModeController(userDefaults: defaults),
            )
        }
    }

    #Preview("Menu") {
        DeveloperOverlayPreview(presentation: .menu)
    }
#endif
