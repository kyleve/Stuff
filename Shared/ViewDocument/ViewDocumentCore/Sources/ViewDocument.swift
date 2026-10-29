import Foundation

/// A finite, read-only view tree. Validation is required before rendering.
public struct ViewDocument: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var root: Node

    public init(schemaVersion: Int, root: Node) {
        self.schemaVersion = schemaVersion
        self.root = root
    }

    public struct Node: Codable, Hashable, Sendable, Identifiable {
        public struct ID: RawRepresentable, Codable, Hashable, Sendable {
            public var rawValue: String
            public init(rawValue: String) {
                self.rawValue = rawValue
            }
        }

        public var id: ID
        public var content: Content
        public var modifiers: [ViewModifierDescriptor]
        public var animation: ViewAnimationDescriptor?
        public var accessibility: Accessibility

        public init(
            id: ID,
            content: Content,
            modifiers: [ViewModifierDescriptor],
            animation: ViewAnimationDescriptor?,
            accessibility: Accessibility,
        ) {
            self.id = id
            self.content = content
            self.modifiers = modifiers
            self.animation = animation
            self.accessibility = accessibility
        }
    }

    public indirect enum Content: Codable, Hashable, Sendable {
        case text(String)
        case image(ViewAssetID)
        case symbol(ViewSymbolID)
        case shape(ViewShapeDescriptor)
        case spacer(minimum: Double)
        case group(axis: Axis, alignment: ViewAlignment, spacing: Double, children: [Node])
    }

    public enum Axis: String, Codable, Hashable, Sendable {
        case horizontal, vertical, overlay
    }

    public enum Accessibility: Codable, Hashable, Sendable {
        case automatic
        case hidden
        case label(String)
        case combine
        case contain
    }
}
