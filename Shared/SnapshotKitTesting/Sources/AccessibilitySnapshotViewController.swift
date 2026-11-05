import AccessibilitySnapshotCore
import AccessibilitySnapshotParser
import AccessibilitySnapshotPreviews
import SwiftUI
import UIKit

/// Wraps a content view controller in AccessibilitySnapshot's SwiftUI renderer
/// so a capture is annotated with the VoiceOver reading order, labels, traits,
/// and activation points. The content is inset first (via ``InsetView``) so an
/// all-element view's region border isn't clipped, and the wrapper is sized to
/// fit the annotations.
final class AccessibilitySnapshotViewController: UIViewController {
    private let source: UIViewController
    private var insetView: UIView {
        source.view
    }

    private var annotations: UIHostingController<PreParsedAccessibilitySnapshotView>?
    private let configuration = AccessibilitySnapshotConfiguration(
        viewRenderingMode: .drawHierarchyInRect,
        colorRenderingMode: .monochrome,
    )

    init(wrapping content: UIViewController) {
        // Give the inset a stable owning controller. The tiled image renderer can then
        // preserve its safe area without temporarily adopting and detaching the source.
        let source = UIViewController()
        source.addChild(content)
        source.view = InsetView(content: content.view)
        content.didMove(toParent: source)
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView(frame: insetView.bounds)
        view.backgroundColor = UIColor(white: 0.9, alpha: 1)
        addChild(source)
        insetView.frame.origin = .zero
        view.addSubview(insetView)
        source.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        annotations?.view.frame = view.bounds
    }

    /// Parses the content's accessibility and sizes the view to fit the resulting
    /// annotations. Must be called while the view is in the hierarchy. Rendering
    /// failures surface loudly rather than producing a blank image.
    func parseAccessibility() {
        annotations?.willMove(toParent: nil)
        annotations?.view.removeFromSuperview()
        annotations?.removeFromParent()
        annotations = nil
        view.frame.size = insetView.bounds.size
        view.layoutIfNeeded()
        insetView.layoutIfNeeded()

        do {
            let image = try insetView.renderToImage(configuration: configuration.rendering)
            // The source keeps its controller and window after image rendering.
            // Parse the same final hierarchy that supplied the captured pixels.
            let markers = AccessibilityHierarchyParser().parseAccessibilityHierarchy(
                in: insetView,
                rotorResultLimit: configuration.rotors.resultLimit,
            ).flattenToElements()
            let rendered = UIHostingController(rootView: PreParsedAccessibilitySnapshotView(
                snapshotImage: image,
                markers: markers,
                configuration: configuration,
                palette: .modern,
                renderSize: insetView.bounds.size,
            ))
            rendered.safeAreaRegions = []
            rendered.view.backgroundColor = UIColor(white: 0.9, alpha: 1)
            let size = rendered.sizeThatFits(in: CGSize(
                width: insetView.bounds.width,
                height: UIView.layoutFittingExpandedSize.height,
            ))
            addChild(rendered)
            rendered.view.frame = CGRect(origin: .zero, size: size)
            view.addSubview(rendered.view)
            rendered.didMove(toParent: self)
            annotations = rendered
            view.frame.size = size
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
