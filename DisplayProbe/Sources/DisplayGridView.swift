import UIKit

/// Draws measured 100-point intervals and a labeled vertical midpoint across its actual bounds.
final class DisplayGridView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // Diagnostic geometry requires the live window scale, which is not an appearance trait.
        let scale = window?.windowScene?.screen.scale ?? contentScaleFactor
        context.setLineWidth(1 / max(scale, 1))
        context.setStrokeColor(UIColor.separator.cgColor)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        for x in stride(from: CGFloat.zero, through: bounds.width, by: 100) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            if x > 0 {
                (DisplayReading.number(x) as NSString).draw(
                    at: CGPoint(x: x, y: bounds.midY),
                    withAttributes: attributes,
                )
            }
        }
        for y in stride(from: CGFloat.zero, through: bounds.height, by: 100) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            (DisplayReading.number(y) as NSString).draw(
                at: CGPoint(x: safeAreaInsets.left, y: y),
                withAttributes: attributes,
            )
        }
        context.strokePath()
        context.setStrokeColor(UIColor.label.cgColor)
        context.move(to: CGPoint(x: bounds.midX, y: 0))
        context.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
        context.strokePath()
    }
}
