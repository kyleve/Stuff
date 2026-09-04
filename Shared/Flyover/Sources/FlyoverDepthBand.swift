import CoreGraphics

/// The visual span occupied by one automatically arranged route depth.
struct FlyoverDepthBand: Equatable, Identifiable {
    enum Kind: Hashable {
        case route(depth: Int)
        case unlinked
    }

    struct ID: Hashable {
        let group: FlyoverGroupID
        let kind: Kind
    }

    let id: ID
    let frame: CGRect

    var kind: Kind {
        id.kind
    }
}
