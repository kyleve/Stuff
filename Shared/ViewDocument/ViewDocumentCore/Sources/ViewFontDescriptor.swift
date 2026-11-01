import Foundation

/// System typography preserves semantic Dynamic Type scaling.
public struct ViewFontDescriptor: Codable, Hashable, Sendable {
    public var size: Size
    /// Nil preserves the semantic text style's system weight.
    public var weight: Weight?
    /// Nil preserves the semantic font's inherited design.
    public var design: Design?

    public init(size: Size, weight: Weight?, design: Design?) {
        self.size = size
        self.weight = weight
        self.design = design
    }

    public enum Size: Codable, Hashable, Sendable {
        case semantic(TextStyle)
        case fixed(Double)
    }

    public enum TextStyle: String, CaseIterable, Codable, Hashable, Sendable {
        case largeTitle, title, title2, title3, headline, subheadline, body, callout, footnote,
             caption, caption2
    }

    public enum Weight: String, Codable, Hashable, Sendable {
        case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black
    }

    public enum Design: String, Codable, Hashable, Sendable {
        case standard, rounded, serif, monospaced
    }
}
