import Foundation

struct ViewDocumentValidator {
    // Bound compounded transforms and authored lengths before native rendering loses precision.
    // Scale-down operations cannot refund these conservative budgets.
    private static let maximumScaleAmplification = 1000.0
    private static let maximumAmplifiedGeometry = 100_000_000.0
    let resources: ViewDocumentResources
    let limits: ViewDocumentLimits
    var identities: Set<ViewDocument.Node.ID> = []
    var animations = 0
    var modifiers = 0
    var amplifiedGeometry = 0.0
    var referencedImages: Set<ViewAssetID> = []
    var referencedSymbols: Set<ViewSymbolID> = []

    mutating func visit(
        _ node: ViewDocument.Node,
        path: String,
        depth: Int,
        inheritedScaleAmplification: Double,
    ) throws {
        try require(depth <= limits.depth, path, "Tree exceeds depth limit")
        try require(!node.id.rawValue.isEmpty, path + ".id", "Empty node identity")
        try require(identities.insert(node.id).inserted, path + ".id", "Duplicate node identity")
        try require(identities.count <= limits.nodes, path, "Tree exceeds node limit")
        try require(
            node.modifiers.count <= limits.modifiersPerNode,
            path + ".modifiers",
            "Node exceeds modifier limit",
        )
        try require(
            node.modifiers.count <= limits.modifiers - modifiers,
            path + ".modifiers",
            "Tree exceeds modifier limit",
        )
        modifiers += node.modifiers.count
        var scaleAmplification = inheritedScaleAmplification
        for (index, modifier) in node.modifiers.enumerated() {
            let modifierPath = path + ".modifiers[\(index)]"
            try validate(modifier, modifierPath)
            if case let .scale(x, y) = modifier {
                scaleAmplification = try amplify(
                    scaleAmplification,
                    by: max(abs(x), abs(y)),
                    path: modifierPath,
                )
            }
        }
        if let animation = node.animation {
            animations += 1
            try require(animations <= limits.animatedNodes, path, "Tree exceeds animation limit")
            try pose(animation.from, path)
            try pose(animation.to, path)
            try pose(animation.staticPose, path)
            let animationScale = [animation.from, animation.to, animation.staticPose]
                .reduce(1.0) { max($0, abs($1.scaleX), abs($1.scaleY)) }
            scaleAmplification = try amplify(
                scaleAmplification,
                by: animationScale,
                path: path + ".animation",
            )
            let offset = [animation.from, animation.to, animation.staticPose]
                .reduce(0.0) { max($0, abs($1.offsetX), abs($1.offsetY)) }
            try includeGeometry(
                offset,
                amplification: scaleAmplification,
                path: path + ".animation",
            )
            try number(animation.duration, path + ".animation.duration", range: 0.1 ... 3600)
            try number(animation.delay, path + ".animation.delay", range: 0 ... 3600)
            switch animation.repetition {
                case .once, .forever: break
                case let .count(count, _): try require(
                        (1 ... 10000).contains(count),
                        path,
                        "Invalid repetition count",
                    )
            }
        }
        for (index, modifier) in node.modifiers.enumerated() {
            try includeGeometry(
                geometryCost(modifier),
                amplification: scaleAmplification,
                path: path + ".modifiers[\(index)]",
            )
        }
        switch node.content {
            case .text: break
            case let .image(asset):
                try require(resources.images.contains(asset), path, "Missing image asset")
                referencedImages.insert(asset)
            case let .raster(image):
                try require(resources.images.contains(image.asset), path, "Missing image asset")
                referencedImages.insert(image.asset)
                switch image.sizing {
                    case .fit, .fill: break
                    case let .tile(scale): try number(
                            scale,
                            path + ".sizing.scale",
                            range: 0.1 ... 10,
                        )
                }
            case let .symbol(symbol):
                try require(resources.symbols.contains(symbol), path, "Missing registered symbol")
                referencedSymbols.insert(symbol)
            case let .shape(value): try shape(value, path)
            case let .spacer(minimum):
                try number(minimum, path, range: 0 ... 100_000)
                try includeGeometry(minimum, amplification: scaleAmplification, path: path)
            case let .group(_, _, spacing, children):
                try number(spacing, path + ".spacing", range: 0 ... 100_000)
                try includeGeometry(
                    spacing * Double(max(0, children.count - 1)),
                    amplification: scaleAmplification,
                    path: path + ".spacing",
                )
                for (index, child) in children.enumerated() {
                    try visit(
                        child,
                        path: path + ".children[\(index)]",
                        depth: depth + 1,
                        inheritedScaleAmplification: scaleAmplification,
                    )
                }
        }
    }

    private func amplify(_ inherited: Double, by scale: Double, path: String) throws -> Double {
        let amplified = inherited * max(1, scale)
        try require(
            amplified <= Self.maximumScaleAmplification,
            path,
            "Combined scale exceeds the supported amplification",
        )
        return amplified
    }

    private mutating func includeGeometry(
        _ points: Double,
        amplification: Double,
        path: String,
    ) throws {
        let cost = points * amplification
        try require(
            cost <= Self.maximumAmplifiedGeometry - amplifiedGeometry,
            path,
            "Combined authored geometry exceeds the rendering budget",
        )
        amplifiedGeometry += cost
    }

    /// Count authored extents conservatively; the host still owns measured layout and font metrics.
    private func geometryCost(_ modifier: ViewModifierDescriptor) -> Double {
        func points(_ dimension: ViewDimension?) -> Double {
            switch dimension {
                case let .points(value), let .scaled(value, _): value
                case nil: 0
            }
        }
        return switch modifier {
            case let .frame(width, height, _): max(points(width), points(height))
            case let .padding(value): 2 * points(value)
            case let .offset(x, y): max(abs(x), abs(y))
            case let .shadow(_, radius, x, y): 2 * radius + max(abs(x), abs(y))
            case let .border(_, _, width): 2 * width
            case .font, .foreground, .scale, .rotation, .opacity, .clip, .background, .blend: 0
        }
    }

    func validate(_ modifier: ViewModifierDescriptor, _ path: String) throws {
        switch modifier {
            case let .font(font):
                switch font.size {
                    case .semantic: break
                    case let .fixed(size): try number(size, path, range: 1 ... 1000)
                }
            case let .foreground(value): try paint(value, path)
            case let .frame(width, height, _):
                if let width { try dimension(width, path) }
                if let height { try dimension(height, path) }
            case let .padding(value): try dimension(value, path)
            case let .offset(x, y): try number(x, path); try number(y, path)
            case let .scale(x, y): try number(x, path, range: -100 ... 100); try number(
                    y,
                    path,
                    range: -100 ... 100,
                )
            case let .rotation(degrees): try number(degrees, path)
            case let .opacity(value): try number(value, path, range: 0 ... 1)
            case let .clip(value): try shape(value, path)
            case let .background(value, fill): try shape(value, path); try paint(fill, path)
            case let .border(value, fill, width):
                try shape(value, path); try paint(fill, path); try number(
                    width,
                    path,
                    range: 0 ... 1000,
                )
            case let .shadow(value, radius, x, y):
                try color(value, path); try number(radius, path, range: 0 ... 1000); try number(
                    x,
                    path,
                ); try number(y, path)
            case .blend: break
        }
    }

    func pose(_ pose: ViewAnimationDescriptor.Pose, _ path: String) throws {
        try number(pose.opacity, path, range: 0 ... 1)
        try number(pose.offsetX, path); try number(pose.offsetY, path)
        try number(pose.scaleX, path, range: -100 ... 100); try number(
            pose.scaleY,
            path,
            range: -100 ... 100,
        )
        try number(pose.rotation, path)
    }

    func dimension(_ dimension: ViewDimension, _ path: String) throws {
        switch dimension {
            case let .points(value), let .scaled(value, _): try number(
                    value,
                    path,
                    range: 0 ... 100_000,
                )
        }
    }

    func shape(_ shape: ViewShapeDescriptor, _ path: String) throws {
        switch shape {
            case .rectangle, .circle, .ellipse: break
            case let .roundedRectangle(radius): try number(radius, path, range: 0 ... 100_000)
        }
    }

    func paint(_ paint: ViewPaint, _ path: String) throws {
        switch paint {
            case let .color(value): try color(value, path)
            case let .linearGradient(stops, start, end):
                try require(
                    (2 ... 64).contains(stops.count),
                    path,
                    "A gradient requires 2 to 64 stops",
                )
                for point in [start, end] {
                    try number(point.x, path, range: 0 ... 1); try number(
                        point.y,
                        path,
                        range: 0 ... 1,
                    )
                }
                var previous = 0.0
                for stop in stops {
                    try color(stop.color, path)
                    try number(stop.location, path, range: previous ... 1)
                    previous = stop.location
                }
        }
    }

    func color(_ color: ViewColorDescriptor, _ path: String, depth: Int = 0) throws {
        try require(depth <= 8, path, "Color composition exceeds depth limit")
        switch color {
            case let .opacity(value, alpha):
                try self.color(value, path, depth: depth + 1)
                try number(alpha, path, range: 0 ... 1)
            case let .mix(first, second, fraction):
                try self.color(first, path, depth: depth + 1)
                try self.color(second, path, depth: depth + 1)
                try number(fraction, path, range: 0 ... 1)
            case .semantic: break
            case let .rgba(red, green, blue, alpha):
                for value in [red, green, blue, alpha] {
                    try number(value, path, range: 0 ... 1)
                }
        }
    }

    func number(
        _ value: Double,
        _ path: String,
        range: ClosedRange<Double> = -100_000 ... 100_000,
    ) throws {
        try require(
            value.isFinite && range.contains(value),
            path,
            "Numeric value is outside the supported range",
        )
    }

    func require(_ condition: Bool, _ path: String, _ reason: String) throws {
        guard condition else { throw ViewDocumentValidationError(path: path, reason: reason) }
    }
}
