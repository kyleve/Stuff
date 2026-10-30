import Foundation

/// Limits are explicit at validation boundaries. Production callers normally use `standard`.
public struct ViewDocumentLimits: Hashable, Sendable {
    public var bytes: Int
    public var depth: Int
    public var nodes: Int
    public var animatedNodes: Int
    public var modifiersPerNode: Int
    public var modifiers: Int

    public init(
        bytes: Int,
        depth: Int,
        nodes: Int,
        animatedNodes: Int,
        modifiersPerNode: Int,
        modifiers: Int,
    ) {
        self.bytes = bytes
        self.depth = depth
        self.nodes = nodes
        self.animatedNodes = animatedNodes
        self.modifiersPerNode = modifiersPerNode
        self.modifiers = modifiers
    }

    public static let standard = Self(
        bytes: 1_048_576,
        depth: 16,
        nodes: 256,
        animatedNodes: 32,
        modifiersPerNode: 32,
        modifiers: 1024,
    )
}
