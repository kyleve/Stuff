import Foundation
import PeriscopeCore

/// Region metadata in canonical manifest order. Reading the hierarchy loads no polygons.
public struct RegionCatalog: Sendable {
    public enum Kind: String, Decodable, Hashable, Sendable {
        case state, federalDistrict, territory, province, country, bloc
    }

    struct Boundary: Decodable, Hashable {
        let file: String
        let product: RegionDataSource.Product
        let year: Int?
    }

    struct Geometry: Decodable, Hashable {
        let tracking: Boundary
        let display: Boundary

        subscript(purpose: RegionGeometryPurpose) -> Boundary {
            switch purpose {
                case .display: display
                case .tracking: tracking
            }
        }
    }

    /// A geographic unit, including countries used to group subdivisions.
    public struct Node: Identifiable, Decodable, Hashable, Sendable {
        public struct ID: RawRepresentable, Codable, Hashable, Sendable {
            public static let unitedStates = Self(rawValue: "united-states")
            public static let canada = Self(rawValue: "canada")

            public let rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public let id: ID
        public let kind: Kind
        public let parentID: ID?
        public let name: String
        public let isLoggable: Bool
        fileprivate let localizationKey: String?
        let geometry: Geometry?

        public var localizedName: String {
            if let localizationKey {
                return String(localized: String.LocalizationValue(localizationKey), bundle: .module)
            }
            return name
        }

        public var region: Region? {
            isLoggable ? Region(unchecked: id.rawValue) : nil
        }

        fileprivate var entry: Entry? {
            region.map { Entry(
                region: $0,
                name: name,
                localizationKey: localizationKey,
            ) }
        }
    }

    /// One loggable region and its naming metadata.
    public struct Entry: Sendable, Hashable {
        public let region: Region
        public let name: String
        public let localizationKey: String?
    }

    /// Every node, including countries that serve only as parents.
    public let nodes: [Node]
    /// Loggable entries preserve their relative manifest order.
    public let entries: [Entry]
    private let byID: [Node.ID: Node]
    private let childrenByParent: [Node.ID: [Node]]

    public static let shared: RegionCatalog = .loadFromBundle()

    private init(nodes: [Node], byID: [Node.ID: Node]) {
        self.nodes = nodes
        self.byID = byID
        entries = nodes.compactMap(\.entry)
        var children: [Node.ID: [Node]] = [:]
        for node in nodes {
            if let parentID = node.parentID {
                children[parentID, default: []].append(node)
            }
        }
        childrenByParent = children
    }

    /// Decode the same wire representation used by the bundled catalog.
    init(manifest: Data) throws {
        let nodes = try JSONDecoder().decode([Node].self, from: manifest)
        // Each resource lives in one group directory under regions/.
        let geometryPath = #/[a-z0-9][a-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9._-]*\.(?:geojson|twkb)/#
        var byID: [Node.ID: Node] = [:]
        func invalid(_ description: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: [], debugDescription: description))
        }
        var vintages: [RegionDataSource.Product: Int] = [:]
        for node in nodes {
            guard !node.id.rawValue.isEmpty, node.id.rawValue != Region.other.rawValue,
                  !node.name.isEmpty
            else {
                throw invalid("Invalid region identifier or name: \(node.id.rawValue)")
            }
            guard (node.kind == .country) == (node.geometry == nil) else {
                throw invalid(
                    "Unexpected geometry file presence for node: \(node.id.rawValue)",
                )
            }
            guard node.kind != .country || !node.isLoggable else {
                throw invalid("Country cannot be a tracking choice: \(node.id.rawValue)")
            }
            if let geometry = node.geometry {
                for purpose in RegionGeometryPurpose.allCases {
                    let boundary = geometry[purpose]
                    guard boundary.file.wholeMatch(of: geometryPath) != nil,
                          boundary.product.purposes.contains(purpose),
                          (boundary.year == nil) == (boundary.product == .original)
                    else {
                        throw invalid("Invalid \(purpose) descriptor for \(node.id.rawValue)")
                    }
                    if let year = boundary.year, let previous = vintages.updateValue(
                        year,
                        forKey: boundary.product,
                    ), year != previous {
                        throw invalid("Conflicting vintages for \(boundary.product)")
                    }
                }
            }
            guard byID.updateValue(node, forKey: node.id) == nil else {
                throw invalid("Duplicate region identifier: \(node.id.rawValue)")
            }
        }
        for node in nodes {
            var ancestor = node
            var seen: Set<Node.ID> = [node.id]
            while let parentID = ancestor.parentID {
                guard let parent = byID[parentID] else {
                    throw invalid("Missing parent \(parentID.rawValue) for \(ancestor.id.rawValue)")
                }
                guard seen.insert(parentID).inserted else {
                    throw invalid("Cyclic region hierarchy at \(parentID.rawValue)")
                }
                ancestor = parent
            }
        }
        self.init(nodes: nodes, byID: byID)
    }

    public func node(id: Node.ID) -> Node? {
        byID[id]
    }

    public func node(for region: Region) -> Node? {
        guard let node = byID[.init(rawValue: region.rawValue)], node.isLoggable else { return nil }
        return node
    }

    public func parent(of node: Node) -> Node? {
        byID[node.id]?.parentID.flatMap { byID[$0] }
    }

    /// Immediate children in manifest order.
    public func children(of node: Node) -> [Node] {
        childrenByParent[node.id] ?? []
    }

    /// Every loggable region in manifest order. The separate `.other` sentinel is omitted.
    public var all: [Region] {
        entries.map(\.region)
    }

    public func contains(id: String) -> Bool {
        byID[.init(rawValue: id)]?.isLoggable == true
    }

    public func entry(for region: Region) -> Entry? {
        node(for: region)?.entry
    }

    public func localizedName(for region: Region) -> String {
        if region == .other {
            return String(localized: "region.other", bundle: .module)
        }
        return node(for: region)?.localizedName ?? region.rawValue
    }

    static func geometryURL(for node: Node, purpose: RegionGeometryPurpose) -> URL? {
        guard let file = node.geometry?[purpose].file else { return nil }
        let path = file as NSString
        return Bundle.module.url(
            forResource: path.lastPathComponent,
            withExtension: nil,
            subdirectory: "regions/\(path.deletingLastPathComponent)",
        )
    }
}

extension RegionCatalog {
    private static let logger = RegionLog.catalog

    private static func loadFromBundle() -> RegionCatalog {
        guard let url = Bundle.module.url(forResource: "regions", withExtension: "json") else {
            logger.missingManifest()
            assertionFailure("Missing bundled regions.json")
            return RegionCatalog(nodes: [], byID: [:])
        }
        do {
            let catalog = try logger.measure(.loadManifest, budget: .milliseconds(100)) {
                try RegionCatalog(manifest: Data(contentsOf: url))
            }
            logger.loaded(regionCount: .shared(.count, catalog.entries.count))
            return catalog
        } catch {
            logger.decodeFailed(error: .restricted(.errorDetails, error))
            assertionFailure("Failed to decode bundled regions.json: \(error)")
            return RegionCatalog(nodes: [], byID: [:])
        }
    }
}
