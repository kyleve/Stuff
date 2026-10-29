import WhereCore

/// The complete visual identity of one app, widget, or intent world.
/// Both inputs are required, including an explicit region appearance resolver.
public struct WherePresentationContext: Sendable, Equatable {
    public let theme: WhereTheme
    public let regionStyles: RegionStyleResolver

    public init(theme: WhereTheme, regionStyles: RegionStyleResolver) {
        self.theme = theme
        self.regionStyles = regionStyles
    }
}
