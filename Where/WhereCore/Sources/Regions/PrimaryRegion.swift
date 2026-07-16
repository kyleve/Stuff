import Foundation
import RegionKit

/// A region the user has chosen as one of their primary places, paired with its
/// customized ``RegionAppearance`` and the position (``order``) it was picked
/// in. The primary set *is* the tracked-region set — the regions the app loads
/// geometry for and attributes GPS against — so picking these both scopes
/// attribution and drives per-region styling.
///
/// `appearance` is optional: a region can be tracked without a stored look yet
/// (the out-of-the-box default set, or a legacy row), in which case the
/// presentation layer falls back to a deterministic default style.
public struct PrimaryRegion: Hashable, Sendable {
    public let region: Region
    public let appearance: RegionAppearance?
    public let order: Int

    public init(region: Region, appearance: RegionAppearance?, order: Int) {
        self.region = region
        self.appearance = appearance
        self.order = order
    }
}
