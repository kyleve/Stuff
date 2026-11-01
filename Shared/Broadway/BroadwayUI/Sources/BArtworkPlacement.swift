import ViewDocumentCore

/// Immutable proof that a host's artwork geometry passed the portable bounds checks.
public struct BArtworkPlacement: Hashable, Sendable {
    public let value: ViewArtworkPlacement

    public init(_ value: ViewArtworkPlacement) throws {
        try value.validate()
        self.value = value
    }
}

/// Essential surface content remains visible when accessibility settings simplify ornament.
public enum BSurfaceLayerRole: String, Codable, Hashable, Sendable {
    case essential, ornament
}
