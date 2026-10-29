import Foundation

public enum ViewShapeDescriptor: Codable, Hashable, Sendable {
    case rectangle
    case roundedRectangle(radius: Double)
    case circle
    case ellipse
}
