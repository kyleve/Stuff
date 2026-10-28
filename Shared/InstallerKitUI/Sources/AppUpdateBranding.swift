import SwiftUI

/// Host-owned, localized app identity. Artwork uses the host's asset bundle and appearance
/// variants.
public struct AppUpdateBranding {
    public let name: String
    public let subtitle: String
    public let icon: Image?

    public init(name: String, subtitle: String, icon: Image? = nil) {
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
    }
}
