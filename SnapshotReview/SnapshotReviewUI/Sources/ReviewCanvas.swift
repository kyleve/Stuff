import SnapshotReviewCore
import SwiftUI
import UIKit

/// One UIKit zoom surface keeps image coordinates and pin hit testing in the same space.
struct ReviewCanvas: UIViewRepresentable {
    let image: CGImage
    let annotations: [ReviewAnnotation]
    let fingerprint: String
    let selected: ReviewAnnotation.ID?
    let isPlacing: Bool
    let command: CanvasCommand
    let style: ReviewStylesheet.Canvas
    let onPoint: (ReviewAnnotation.Point) -> Void
    let onSelect: (ReviewAnnotation.ID) -> Void

    struct CanvasCommand: Equatable {
        enum Action { case fit, actual, zoomIn, zoomOut }
        var action: Action = .fit
        var revision: Int = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = CanvasScrollView()
        scroll.backgroundColor = .systemBackground
        scroll
            .onLayout = { [weak coordinator = context.coordinator] view in
                coordinator?.fitInitially(view)
            }
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 0.01
        scroll.maximumZoomScale = 8
        scroll.addSubview(context.coordinator.content)
        context.coordinator.content.addSubview(context.coordinator.imageView)
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.place(_:)),
        )
        tap.delegate = context.coordinator
        context.coordinator.content.addGestureRecognizer(tap)
        scroll.accessibilityLabel = "Snapshot image. Use Add Point to place an annotation."
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.update(self, scroll: scroll)
    }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate,
        UIGestureRecognizerDelegate
    {
        var parent: ReviewCanvas
        let content = UIView()
        let imageView = UIImageView()
        private var currentImage: CGImage?
        private var needsInitialFit = true
        private var pins: [UIButton] = []
        private var command: CanvasCommand?
        private var lastSelected: ReviewAnnotation.ID?
        init(_ parent: ReviewCanvas) {
            self.parent = parent
        }

        func fitInitially(_ scroll: UIScrollView) {
            guard needsInitialFit, currentImage != nil, scroll.bounds.width > 0,
                  scroll.bounds.height > 0 else { return }
            needsInitialFit = false
            let fit = min(
                scroll.bounds.width / content.bounds.width,
                scroll.bounds.height / content.bounds.height,
            )
            scroll.setZoomScale(fit, animated: false)
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            content
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updatePinScale(scrollView)
        }

        func updatePinScale(_ scroll: UIScrollView) {
            for pin in pins {
                pin.transform = CGAffineTransform(
                    scaleX: 1 / scroll.zoomScale,
                    y: 1 / scroll.zoomScale,
                )
            }
        }

        func update(_ parent: ReviewCanvas, scroll: UIScrollView) {
            self.parent = parent
            let changed = currentImage !== parent.image
            if changed {
                let previousOffset = scroll.contentOffset
                let oldSize = scroll.contentSize
                let previousZoom = scroll.zoomScale
                let first = currentImage == nil
                currentImage = parent.image
                scroll.setZoomScale(1, animated: false)
                let size = CGSize(width: parent.image.width, height: parent.image.height)
                content.frame = CGRect(origin: .zero, size: size)
                imageView.frame = content.bounds
                imageView.image = UIImage(cgImage: parent.image)
                scroll.contentSize = size
                scroll.layoutIfNeeded()
                let fit = min(
                    max(1, scroll.bounds.width) / size.width,
                    max(1, scroll.bounds.height) / size.height,
                )
                scroll.setZoomScale(first ? fit : previousZoom, animated: false)
                scroll.contentOffset = ReviewCanvasGeometry.offset(
                    previous: previousOffset,
                    oldContent: oldSize,
                    newContent: scroll.contentSize,
                    viewport: scroll.bounds.size,
                )
            }
            for pin in pins {
                pin.removeFromSuperview()
            }
            pins = []
            for (index, annotation) in parent.annotations.enumerated() {
                guard let point = annotation.point else { continue }
                let pin = UIButton(type: .system)
                pin.setTitle("\(index + 1)", for: .normal)
                pin
                    .backgroundColor = UIColor(annotation.fingerprint == parent.fingerprint ? parent
                        .style.pinFill : parent.style.outdatedFill)
                pin.setTitleColor(.white, for: .normal)
                pin.bounds = CGRect(
                    x: 0,
                    y: 0,
                    width: parent.style.pinSize,
                    height: parent.style.pinSize,
                )
                pin.layer.cornerRadius = parent.style.pinSize / 2
                pin.layer.borderWidth = annotation.id == parent.selected ? parent.style
                    .selectedBorderWidth : parent.style.borderWidth
                pin.layer.borderColor = UIColor.label.cgColor
                pin.center = CGPoint(
                    x: point.x * content.bounds.width,
                    y: point.y * content.bounds.height,
                )
                pin
                    .accessibilityLabel = "Annotation \(index + 1): \(annotation.text)" +
                    (annotation.fingerprint == parent.fingerprint ? "" : ", outdated point")
                pin.addAction(
                    UIAction { [weak self] _ in self?.parent.onSelect(annotation.id) },
                    for: .touchUpInside,
                )
                content.addSubview(pin)
                pins.append(pin)
            }
            fitInitially(scroll)
            updatePinScale(scroll)
            if command != parent.command {
                command = parent.command
                let fit = min(
                    max(1, scroll.bounds.width) / content.bounds.width,
                    max(1, scroll.bounds.height) / content.bounds.height,
                )
                let scale: CGFloat = switch parent.command.action {
                    case .fit: fit
                    case .actual: 1 / scroll.traitCollection.displayScale
                    case .zoomIn: min(8, scroll.zoomScale * 1.5)
                    case .zoomOut: max(0.01, scroll.zoomScale / 1.5)
                }
                scroll.setZoomScale(scale, animated: false)
            }
            if lastSelected != parent.selected {
                lastSelected = parent.selected
                if let annotation = parent.annotations.first(where: { $0.id == parent.selected }),
                   let point = annotation.point
                {
                    let x = point.x * content.bounds.width * scroll.zoomScale - scroll.bounds
                        .width / 2
                    let y = point.y * content.bounds.height * scroll.zoomScale - scroll.bounds
                        .height / 2
                    scroll.setContentOffset(
                        CGPoint(x: min(
                            max(0, x),
                            max(0, scroll.contentSize.width - scroll.bounds.width),
                        ), y: min(
                            max(0, y),
                            max(0, scroll.contentSize.height - scroll.bounds.height),
                        )),
                        animated: false,
                    )
                }
            }
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        @objc func place(_ gesture: UITapGestureRecognizer) {
            guard parent.isPlacing, !(gesture.view is UIButton) else { return }
            let location = gesture.location(in: content)
            if let point = ReviewCanvasGeometry
                .point(at: location, bounds: content.bounds) { parent.onPoint(point) }
        }
    }
}

@MainActor final class CanvasScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }
}
