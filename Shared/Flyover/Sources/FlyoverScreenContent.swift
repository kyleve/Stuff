import SnapshotKit
import SwiftUI

/// Applies Flyover traits and sizing to one registered screen's selected content.
struct FlyoverScreenContent<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    let isOverview: Bool
    @State private var content: AnyView?
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

        Group {
            if let content {
                switch screen.navigationContainer {
                    case .stack:
                        NavigationStack {
                            content
                        }
                    case .none:
                        content
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
            content = nil
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
                content = loadedContent
            }
        }
        .onDisappear {
            content = nil
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
}
