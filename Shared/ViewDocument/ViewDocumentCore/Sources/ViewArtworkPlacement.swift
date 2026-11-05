import Foundation

/// Bounded artwork geometry, independent of the host's layout and interaction bounds.
public struct ViewArtworkPlacement: Codable, Hashable, Sendable {
    public var anchor: ViewAlignment
    public var size: Size
    public var offset: Offset
    public var plane: Plane
    public var outsets: Outsets

    public init(anchor: ViewAlignment, size: Size, offset: Offset, plane: Plane, outsets: Outsets) {
        self.anchor = anchor
        self.size = size
        self.offset = offset
        self.plane = plane
        self.outsets = outsets
    }

    public enum Plane: String, Codable, Hashable, Sendable {
        case interior, exterior
    }

    /// Relative sizes are capped in points. Fixed sizes shrink uniformly for narrow hosts.
    public enum Size: Codable, Hashable, Sendable {
        case fixed(width: Double, height: Double)
        case relative(width: Double, height: Double, maximumWidth: Double, maximumHeight: Double)
    }

    public struct Offset: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x; self.y = y
        }

        public static let zero = Self(x: 0, y: 0)
    }

    public struct Outsets: Codable, Hashable, Sendable {
        public var top: Double
        public var leading: Double
        public var bottom: Double
        public var trailing: Double
        public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
            self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
        }

        public static let zero = Self(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    public func validate() throws {
        func number(_ value: Double, _ field: String, _ range: ClosedRange<Double>) throws {
            guard value.isFinite, range.contains(value) else {
                throw ViewDocumentValidationError(
                    path: "$.placement." + field,
                    reason: "Invalid artwork geometry",
                )
            }
        }
        switch size {
            case let .fixed(width, height):
                try number(width, "width", 1 ... 2048)
                try number(height, "height", 1 ... 2048)
            case let .relative(width, height, maximumWidth, maximumHeight):
                try number(width, "width", 0.001 ... 2)
                try number(height, "height", 0.001 ... 2)
                try number(maximumWidth, "maximumWidth", 1 ... 2048)
                try number(maximumHeight, "maximumHeight", 1 ... 2048)
        }
        try number(offset.x, "offset.x", -2048 ... 2048)
        try number(offset.y, "offset.y", -2048 ... 2048)
        for value in [outsets.top, outsets.leading, outsets.bottom, outsets.trailing] {
            try number(value, "outsets", 0 ... 128)
        }
        if plane == .interior, outsets != .zero {
            throw ViewDocumentValidationError(
                path: "$.placement.outsets",
                reason: "Interior artwork cannot overflow",
            )
        }
    }

    /// The renderer must clip to paintBounds; transforms cannot enlarge that contract.
    public func geometry(in host: Extent, rightToLeft: Bool) -> Geometry {
        geometry(in: host, rightToLeft: rightToLeft, maximumOutsets: nil)
    }

    /// The host can reduce its reserved gutters without reducing native content width.
    public func geometry(
        in host: Extent,
        rightToLeft: Bool,
        maximumOutsets: Outsets?,
    ) -> Geometry {
        let width = host.width.isFinite ? max(0, Double(host.width)) : 0
        let height = host.height.isFinite ? max(0, Double(host.height)) : 0
        let proposed = switch size {
            case let .fixed(width, height): Extent(width: width, height: height)
            case let .relative(x, y, maximumWidth, maximumHeight):
                Extent(width: min(width * x, maximumWidth), height: min(height * y, maximumHeight))
        }
        var allowanceScale = 1.0
        if let maximumOutsets {
            func constrain(_ requested: Double, _ available: Double) {
                guard requested > 0 else { return }
                let available = available.isFinite ? max(0, available) : 0
                allowanceScale = min(allowanceScale, available / requested)
            }
            constrain(outsets.top, maximumOutsets.top)
            constrain(outsets.leading, maximumOutsets.leading)
            constrain(outsets.bottom, maximumOutsets.bottom)
            constrain(outsets.trailing, maximumOutsets.trailing)
        }
        let scale = proposed.width > 0 ? min(allowanceScale, width / Double(proposed.width)) : 0
        let artworkWidth = Double(proposed.width) * scale
        let artworkHeight = Double(proposed.height) * scale
        let horizontal: Double = switch anchor {
            case .topLeading, .leading, .bottomLeading: rightToLeft ? 1 : 0
            case .top, .center, .bottom: 0.5
            case .topTrailing, .trailing, .bottomTrailing: rightToLeft ? 0 : 1
        }
        let vertical: Double = switch anchor {
            case .topLeading, .top, .topTrailing: 0
            case .leading, .center, .trailing: 0.5
            case .bottomLeading, .bottom, .bottomTrailing: 1
        }
        let left = (rightToLeft ? outsets.trailing : outsets.leading) * allowanceScale
        let right = (rightToLeft ? outsets.leading : outsets.trailing) * allowanceScale
        let x = (width - artworkWidth) * horizontal + offset.x * scale * (rightToLeft ? -1 : 1)
        let y = (height - artworkHeight) * vertical + offset.y * scale
        return Geometry(
            frame: Frame(
                x: x,
                y: y,
                width: artworkWidth,
                height: artworkHeight,
            ),
            paintBounds: Frame(
                x: -left,
                y: -outsets.top * allowanceScale,
                width: width + left + right,
                height: height + (outsets.top + outsets.bottom) * allowanceScale,
            ),
        )
    }

    public struct Extent: Equatable, Sendable {
        public let width: Double
        public let height: Double
        public init(width: Double, height: Double) {
            self.width = width; self.height = height
        }
    }

    public struct Frame: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
        public var size: Extent {
            .init(width: width, height: height)
        }

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    public struct Geometry: Equatable, Sendable {
        public let frame: Frame
        public let paintBounds: Frame
    }
}
