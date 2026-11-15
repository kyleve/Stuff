import Foundation

/// Ordered operations; a modifier applies to the result of all preceding operations.
public enum ViewModifierDescriptor: Codable, Hashable, Sendable {
    case font(ViewFontDescriptor)
    case foreground(ViewPaint)
    case frame(width: ViewDimension?, height: ViewDimension?, alignment: ViewAlignment)
    case padding(ViewDimension)
    case offset(x: Double, y: Double)
    case scale(x: Double, y: Double)
    case rotation(degrees: Double)
    case opacity(Double)
    case clip(ViewShapeDescriptor)
    case background(shape: ViewShapeDescriptor, paint: ViewPaint)
    case border(shape: ViewShapeDescriptor, paint: ViewPaint, width: Double)
    case shadow(color: ViewColorDescriptor, radius: Double, x: Double, y: Double)
    case blend(Blend)

    public enum Blend: String, Codable, Hashable, Sendable {
        case normal, multiply, screen, overlay, darken, lighten, plusLighter
    }
}
