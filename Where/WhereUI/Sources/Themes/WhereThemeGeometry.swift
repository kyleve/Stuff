import CoreGraphics

public struct WhereThemeSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var size: CGSize {
        .init(width: width, height: height)
    }
}

public struct WhereThemePoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var point: CGPoint {
        .init(x: x, y: y)
    }
}
