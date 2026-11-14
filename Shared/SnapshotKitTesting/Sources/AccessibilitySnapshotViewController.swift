import AccessibilitySnapshotCore
import AccessibilitySnapshotPreviews
import UIKit

/// Wraps a content view controller in AccessibilitySnapshot's SwiftUI renderer
/// so a capture is annotated with the VoiceOver reading order, labels, traits,
/// and activation points. The content is inset first (via ``InsetView``) so an
/// all-element view's region border isn't clipped, and the wrapper is sized to
/// fit the annotations.
final class AccessibilitySnapshotViewController: UIViewController {
    /// Upstream UIView+ImageRendering's tile limit, in points. Re-check on upgrades.
    private static let upstreamTileSideLength: CGFloat = 2000
    private let content: UIViewController
    private let insetView: InsetView

    private var snapshotView: SwiftUIAccessibilitySnapshotContainerView {
        guard let snapshotView = view as? SwiftUIAccessibilitySnapshotContainerView else {
            preconditionFailure(
                "AccessibilitySnapshotViewController.view must be a SwiftUIAccessibilitySnapshotContainerView.",
            )
        }
        return snapshotView
    }

    init(wrapping content: UIViewController) {
        self.content = content
        insetView = InsetView(content: content.view)
        super.init(nibName: nil, bundle: nil)
        addChild(content)
        content.didMove(toParent: self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = SwiftUIAccessibilitySnapshotContainerView(
            containedView: insetView,
            snapshotConfiguration: AccessibilitySnapshotConfiguration(
                viewRenderingMode: .drawHierarchyInRect,
                colorRenderingMode: .monochrome,
            ),
        )
        container.addSubview(insetView)
        view = container
    }

    /// Parses accessibility without expanding the capture viewport.
    /// Must be called while the view is in the hierarchy. Rendering
    /// failures surface loudly rather than producing a blank image.
    func parseAccessibility() {
        // The upstream tiled renderer temporarily adopts the padding view.
        let requiresTiling = insetView.bounds.width > Self.upstreamTileSideLength
            || insetView.bounds.height > Self.upstreamTileSideLength
        if requiresTiling {
            content.willMove(toParent: nil)
            content.removeFromParent()
        }
        defer {
            if requiresTiling {
                addChild(content)
                content.didMove(toParent: self)
            }
        }
        do {
            try SnapshotAccessibilityViewport.withUnclippedNavigationBars(in: insetView) {
                try snapshotView.parseAccessibility()
            }
        } catch let ImageRenderingError.containedViewExceedsMaximumSize(viewSize, maximumSize) {
            preconditionFailure(
                "Accessibility snapshot content \(viewSize) exceeds the maximum renderable size \(maximumSize); "
                    + "reduce the view size or render in full color.",
            )
        } catch ImageRenderingError.containedViewHasUnsupportedTransform {
            preconditionFailure(
                "Accessibility snapshot content has an unsupported transform; use an identity transform.",
            )
        } catch let ImageRenderingError.containedViewHasZeroSize(viewSize) {
            preconditionFailure(
                "Accessibility snapshot content has a zero dimension \(viewSize); size it before capture.",
            )
        } catch {
            preconditionFailure("Failed to render accessibility snapshot image: \(error)")
        }
    }

    /// Expand after the final parse, keeping preparation at the subject's size.
    func sizeToFitAnnotations() {
        snapshotView.sizeToFit()
    }
}

/// Insets its content so an accessibility region border drawn around an
/// all-element view isn't clipped at the edges.
private final class InsetView: UIView {
    private static let inset: CGFloat = 8

    /// This wrapper adds annotation padding, not device clearance. Native insets
    /// here can move centered content between image rendering and marker parsing.
    override var safeAreaInsets: UIEdgeInsets {
        .zero
    }

    init(content: UIView) {
        let frame = content.frame.inset(
            by: UIEdgeInsets(
                top: -Self.inset,
                left: -Self.inset,
                bottom: -Self.inset,
                right: -Self.inset,
            ),
        )
        super.init(frame: frame)
        content.frame.origin = CGPoint(x: Self.inset, y: Self.inset)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
