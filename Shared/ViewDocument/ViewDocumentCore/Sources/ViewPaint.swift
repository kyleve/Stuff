import Foundation

/// A solid color or linear gradient in normalized local coordinates.
public enum ViewPaint: Codable, Hashable, Sendable {
    case color(ViewColorDescriptor)
    case linearGradient(stops: [Stop], start: Point, end: Point)

    public struct Stop: Codable, Hashable, Sendable {
        public var color: ViewColorDescriptor
        public var location: Double
        public init(color: ViewColorDescriptor, location: Double) {
            self.color = color
            self.location = location
        }
    }

    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x; self.y = y
        }
    }
}
