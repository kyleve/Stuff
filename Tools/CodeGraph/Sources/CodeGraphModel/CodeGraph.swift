import Foundation

/// A complete snapshot of a repository's types and the relationships between
/// them, produced by `code-graph-extract` and rendered by the viewer.
///
/// Everything discovered is kept; narrowing the graph down to something
/// readable is purely a viewer-side filtering concern.
public struct CodeGraph: Codable, Sendable, Hashable {
    /// Bumped when the on-disk shape changes so the viewer can reject snapshots
    /// it cannot read.
    public var schemaVersion: Int
    /// When the snapshot was generated.
    public var generatedAt: Date
    /// Absolute path of the repository the snapshot was taken from.
    public var repoPath: String
    /// `git` commit the snapshot reflects, when known.
    public var commit: String?
    public var modules: [Module]
    public var nodes: [Node]
    public var edges: [Edge]

    public init(
        schemaVersion: Int = CodeGraph.currentSchemaVersion,
        generatedAt: Date,
        repoPath: String,
        commit: String? = nil,
        modules: [Module],
        nodes: [Node],
        edges: [Edge],
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.repoPath = repoPath
        self.commit = commit
        self.modules = modules
        self.nodes = nodes
        self.edges = edges
    }

    /// The schema version this build of the model produces and understands.
    public static let currentSchemaVersion = 1
}

extension CodeGraph {
    /// Decode a snapshot from `graph.json` data using the shared coding config.
    public static func decoded(from data: Data) throws -> CodeGraph {
        try CodeGraphCoding.decoder.decode(CodeGraph.self, from: data)
    }

    /// Encode this snapshot to pretty-printed `graph.json` data.
    public func encoded() throws -> Data {
        try CodeGraphCoding.encoder.encode(self)
    }

    /// A small hand-written snapshot bundled for tests, previews, and for
    /// developing the viewer before the extractor produces real data.
    public static func sample() throws -> CodeGraph {
        guard
            let url = Bundle.module.url(forResource: "sample-graph", withExtension: "json")
        else {
            throw CodeGraphError.resourceMissing("sample-graph.json")
        }
        return try decoded(from: Data(contentsOf: url))
    }
}

/// Errors surfaced by the model layer.
public enum CodeGraphError: Error, CustomStringConvertible {
    case resourceMissing(String)

    public var description: String {
        switch self {
            case let .resourceMissing(name):
                "Bundled resource is missing: \(name)"
        }
    }
}
