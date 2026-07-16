import UIKit

/// Above this dimension (points) in either axis, `drawHierarchy(in:afterScreenUpdates:)`
/// returns a blank image (a long-standing UIKit bug, still reproducing on the
/// target toolchain — verified by a probe during development). Views at or above
/// it are captured in tiles no larger than this and stitched back together.
private let tileDimension: CGFloat = 2000

/// Hosts a content view controller inside a plain wrapper view that acts as a
/// movable viewport into the (potentially larger) content view — the mechanism
/// tile-and-stitch uses to capture oversized views in bug-free chunks.
final class SnapshotWrappingViewController: UIViewController {
    let content: UIViewController

    init(_ content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
        addChild(content)
        content.didMove(toParent: self)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()
        // The content view is a plain subview (not this VC's own `view`) so the
        // container's layout-margin handling doesn't perturb the content.
        content.view.autoresizingMask = []
        view.addSubview(content.view)
        view.frame.size = content.view.frame.size
        content.view.frame.origin = .zero
    }
}

/// Captures the wrapping controller's content view in `tileDimension`-sized tiles
/// and stitches them into one image, working around the oversized-view empty-image
/// bug. For content within a single tile this is a single full-size capture.
@MainActor
func tileAndStitchImage(of wrappingViewController: SnapshotWrappingViewController) -> UIImage {
    guard let contentView = wrappingViewController.content.view else {
        preconditionFailure("SnapshotWrappingViewController content has no view to capture.")
    }
    let frameView = wrappingViewController.view!
    frameView.addSubview(contentView)

    let contentSize = contentView.bounds.size
    var tileRect = CGRect.zero
    var rows: [[UIImage]] = []

    while tileRect.minY < contentSize.height {
        var row: [UIImage] = []
        tileRect.origin.x = 0
        tileRect.size.height = min(tileRect.minY + tileDimension, contentSize.height) - tileRect
            .minY

        while tileRect.minX < contentSize.width {
            tileRect.size.width = min(tileRect.minX + tileDimension, contentSize.width) - tileRect
                .minX

            frameView.frame.size = tileRect.size
            contentView.frame.origin = CGPoint(x: -tileRect.minX, y: -tileRect.minY)
            CATransaction.performWithoutAnimation(frameView.layoutIfNeeded)

            let tile = UIGraphicsImageRenderer(bounds: frameView.bounds).image { _ in
                frameView.drawHierarchy(in: frameView.bounds, afterScreenUpdates: true)
            }
            row.append(tile)
            tileRect.origin.x += tileDimension
        }

        rows.append(row)
        tileRect.origin.x = 0
        tileRect.origin.y += tileDimension
    }

    return UIGraphicsImageRenderer(bounds: CGRect(origin: .zero, size: contentSize)).image { _ in
        var drawPoint = CGPoint.zero
        for row in rows {
            for tile in row {
                tile.draw(at: drawPoint)
                drawPoint.x += tile.size.width
            }
            drawPoint.x = 0
            drawPoint.y += row.first?.size.height ?? 0
        }
    }
}
