import SnapshotKit
import SwiftUI

/// Applies Flyover traits and sizing to one registered screen's selected content.
struct FlyoverScreenContent<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    let isOverview: Bool
    @State private var loadedContent: LoadedContent?
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        let state = model.state(for: screen)
        let variant = model.variant(for: screen)
        let size = model.size(for: screen)
        let scale = overviewScale(for: size)
        let contentID = ContentID(
            variantID: variant.id,
            generation: state.generation,
            isOverview: isOverview,
        )
        let previewLoadKey = model.previewLoadKey(for: screen)

        Group {
            if let loadedContent, loadedContent.id == contentID {
                switch screen.navigationContainer {
                    case .stack:
                        NavigationStack {
                            loadedContent.content
                        }
                    case .none:
                        loadedContent.content
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Loading \(screen.title)")
            }
        }
        .frame(width: size.width, height: size.height)
        .snapshotTraits(
            model.configuration(
                for: screen,
                systemColorScheme: systemColorScheme,
            ),
        )
        .environment(\.isCapturingSnapshot, isOverview)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(
            width: size.width * scale,
            height: size.height * scale,
            alignment: .topLeading,
        )
        .clipShape(
            .rect(cornerRadius: isOverview ? stylesheet.screenContent.cornerRadius : 0),
        )
        .allowsHitTesting(isOverview == false)
        .task(id: contentID) {
            if loadedContent?.id == contentID {
                if isOverview {
                    model.previewReadiness.beganLoading(previewLoadKey)
                    model.previewReadiness.finishedLoading(previewLoadKey)
                }
                return
            }
            loadedContent = nil
            if isOverview {
                model.previewReadiness.beganLoading(previewLoadKey)
            }
            var didFinishLoading = false
            defer {
                if isOverview, didFinishLoading == false {
                    model.previewReadiness.unloaded(previewLoadKey)
                }
            }
            await model.contentLoadCoordinator.perform {
                guard Task.isCancelled == false else {
                    return
                }
                let loadedContent = if isOverview {
                    variant.overviewContent()
                } else {
                    variant.focusedContent()
                }
                guard Task.isCancelled == false else {
                    return
                }
                self.loadedContent = LoadedContent(id: contentID, content: loadedContent)
                didFinishLoading = true
                if isOverview {
                    model.previewReadiness.finishedLoading(previewLoadKey)
                }
            }
        }
        .onDisappear {
            if isOverview {
                model.previewReadiness.unloaded(previewLoadKey)
            }
        }
    }

    private func overviewScale(for size: CGSize) -> CGFloat {
        guard isOverview else {
            return 1
        }
        let maximumSize = stylesheet.screenContent.overviewMaximumSize
        return min(maximumSize.width / size.width, maximumSize.height / size.height, 1)
    }

    private struct ContentID: Hashable {
        let variantID: FlyoverVariantID
        let generation: Int
        let isOverview: Bool
    }

    private struct LoadedContent {
        let id: ContentID
        let content: AnyView
    }
}
