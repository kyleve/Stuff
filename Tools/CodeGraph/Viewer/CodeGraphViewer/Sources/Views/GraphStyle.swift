import CodeGraphModel
import SwiftUI

/// Visual vocabulary for the graph: colors, glyphs, and line styling that make
/// node kinds and edge kinds distinguishable at a glance.
enum GraphStyle {
    static func color(for kind: NodeKind) -> Color {
        switch kind {
            case .class: .blue
            case .struct: .green
            case .enum: .orange
            case .protocol: .purple
            case .actor: .pink
            case .extension: .teal
            case .typeAlias: .mint
            case .associatedType: .indigo
            case .method: .cyan
            case .property: .gray
            case .initializer: .brown
            case .subscript: .gray
            case .enumCase: .yellow
            case .function: .cyan
            case .module: .secondary
            case .other: .gray
        }
    }

    static func symbol(for kind: NodeKind) -> String {
        switch kind {
            case .class: "c.square.fill"
            case .struct: "s.square.fill"
            case .enum: "e.square.fill"
            case .protocol: "p.square.fill"
            case .actor: "a.square.fill"
            case .extension: "puzzlepiece.extension.fill"
            case .typeAlias: "equal.square.fill"
            case .associatedType: "a.square"
            case .method: "function"
            case .property: "circle.fill"
            case .initializer: "wand.and.stars"
            case .subscript: "list.bullet.indent"
            case .enumCase: "smallcircle.filled.circle"
            case .function: "function"
            case .module: "shippingbox.fill"
            case .other: "questionmark.square"
        }
    }

    static func color(for origin: Origin) -> Color {
        switch origin {
            case .firstParty: .primary
            case .test: .orange
            case .external: .secondary
        }
    }

    static func color(for kind: EdgeKind) -> Color {
        switch kind {
            case .inheritance: .blue
            case .conformance: .purple
            case .override: .indigo
            case .member: .gray
            case .propertyType: .green
            case .paramOrReturnType: .teal
            case .construction: .orange
            case .genericConstraint: .pink
            case .associatedType: .mint
            case .moduleDependency: .secondary
            case .reference: .gray
        }
    }

    /// Dash pattern for an edge: structural edges are solid, data-flow edges
    /// dashed, so usage relationships read as lighter than "is-a"/ownership.
    static func dash(for kind: EdgeKind) -> [CGFloat] {
        switch kind {
            case .inheritance, .conformance, .override, .member, .moduleDependency: []
            case .propertyType, .paramOrReturnType, .construction, .genericConstraint,
                 .associatedType, .reference: [5, 4]
        }
    }

    static func lineWidth(for kind: EdgeKind) -> CGFloat {
        switch kind {
            case .inheritance, .conformance: 2.0
            case .override, .member, .moduleDependency: 1.5
            case .propertyType, .paramOrReturnType, .construction, .genericConstraint,
                 .associatedType, .reference: 1.2
        }
    }
}
