import AccessibilitySnapshotCore
import UIKit

/// Wraps a content view controller in an `AccessibilitySnapshotView` so a capture
/// is annotated with the VoiceOver reading order, labels, traits, and activation
/// points. The content is inset first (via ``InsetView``) so an all-element view's
/// region border isn't clipped, and the wrapper is sized to fit the annotations.
final class AccessibilitySnapshotViewController: UIViewController {
    private let content: UIViewController

    private var snapshotView: AccessibilitySnapshotView {
        guard let snapshotView = view as? AccessibilitySnapshotView else {
            preconditionFailure(
                "AccessibilitySnapshotViewController.view must be an AccessibilitySnapshotView.",
            )
        }
        return snapshotView
    }

    init(wrapping content: UIViewController, ownsContent: Bool) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        if ownsContent {
            addChild(content)
            content.didMove(toParent: self)
        }
        // AccessibilitySnapshot temporarily hosts oversized contained views in
        // its own renderer. Those controllers stay unparented so that re-hosting
        // does not violate UIKit containment for tall, full-content captures.
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = AccessibilitySnapshotView(
            containedView: InsetView(content: content.view),
            snapshotConfiguration: AccessibilitySnapshotConfiguration(
                viewRenderingMode: .drawHierarchyInRect,
                colorRenderingMode: .monochrome,
            ),
        )
    }

    /// Parses the content's accessibility and sizes the view to fit the resulting
    /// annotations. Must be called while the view is in the hierarchy. Rendering
    /// failures surface loudly rather than producing a blank image.
    func parseAccessibility() {
        do {
            try snapshotView.parseAccessibility()
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
        snapshotView.sizeToFit()
    }
}

/// Insets its content so an accessibility region border drawn around an
/// all-element view isn't clipped at the edges.
private final class InsetView: UIView {
    private static let inset: CGFloat = 8

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
