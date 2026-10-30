import BroadwayCore
import BroadwayUI
import ViewDocumentCore

/// Read-only illustrated content. Native labels, controls, and geographic data remain in the host.
public struct WhereThemeArtwork: Codable, Hashable, Sendable, Identifiable {
    public struct ID: RawRepresentable, Codable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public var id: ID
    public var document: ViewDocument
    public var placement: ViewArtworkPlacement
    public var role: BSurfaceLayerRole
    public var opacity: BThemeValue<Double>

    public init(
        id: ID,
        document: ViewDocument,
        placement: ViewArtworkPlacement,
        role: BSurfaceLayerRole,
        opacity: BThemeValue<Double>,
    ) {
        self.id = id; self.document = document; self.placement = placement
        self.role = role; self.opacity = opacity
    }
}

/// Native passport marks retain their component's document-owned geometry and geographic inputs.
public enum WhereThemeNativeArtwork: String, Codable, CaseIterable, Hashable, Sendable {
    case rosette, microprint, watermark, stamp, regionPattern
}
