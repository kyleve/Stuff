import Foundation

/// An approved image and its behavior within the proposed layout bounds.
public struct ViewImageDescriptor: Codable, Hashable, Sendable {
    public var asset: ViewAssetID
    public var sizing: Sizing

    public init(asset: ViewAssetID, sizing: Sizing) {
        self.asset = asset
        self.sizing = sizing
    }

    public enum Sizing: Codable, Hashable, Sendable {
        case fit
        case fill
        /// Scale relative to the image's intrinsic point size. Tiles never create document nodes.
        case tile(scale: Double)
    }
}
