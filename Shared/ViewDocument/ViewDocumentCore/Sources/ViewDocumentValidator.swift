import Foundation

struct ViewDocumentValidator {
    let resources: ViewDocumentResources
    let limits: ViewDocumentLimits
    var identities: Set<ViewDocument.Node.ID> = []
    var animations = 0
    var referencedImages: Set<ViewAssetID> = []
    var referencedSymbols: Set<ViewSymbolID> = []

    mutating func visit(_ node: ViewDocument.Node, path: String, depth: Int) throws {
        try require(depth <= limits.depth, path, "Tree exceeds depth limit")
        try require(!node.id.rawValue.isEmpty, path + ".id", "Empty node identity")
        try require(identities.insert(node.id).inserted, path + ".id", "Duplicate node identity")
        try require(identities.count <= limits.nodes, path, "Tree exceeds node limit")
        switch node.content {
            case .text: break
            case let .image(asset):
                try require(
                    resources.images.contains(asset),
                    path,
                    "Missing image asset",
                )
                referencedImages.insert(asset)
            case let .symbol(symbol):
                try require(
                    resources.symbols.contains(symbol),
                    path,
                    "Missing registered symbol",
                )
                referencedSymbols.insert(symbol)
            case let .shape(value): try shape(value, path)
            case let .spacer(minimum): try number(minimum, path, range: 0 ... 100_000)
            case let .group(_, _, spacing, children):
                try number(spacing, path + ".spacing", range: 0 ... 100_000)
                for (index, child) in children.enumerated() {
                    try visit(child, path: path + ".children[\(index)]", depth: depth + 1)
                }
        }
        for (index, modifier) in node.modifiers.enumerated() {
            try validate(modifier, path + ".modifiers[\(index)]")
        }
        if let animation = node.animation {
            animations += 1
            try require(animations <= limits.animatedNodes, path, "Tree exceeds animation limit")
            try pose(animation.from, path)
            try pose(animation.to, path)
            try pose(animation.staticPose, path)
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

    func color(_ color: ViewColorDescriptor, _ path: String) throws {
        switch color {
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
