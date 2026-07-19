import RegionKit
import SwiftUI
import WhereCore

/// Resolves a `Region` to its `RegionStyle`, using the user's picked
/// ``RegionAppearance``s when present and falling back to the deterministic
/// default look otherwise.
///
/// Injected into the view environment (`\.regionStyles`) by `whereBroadwayRoot`,
/// so every surface resolves the *same* styles from a single seeded value rather
/// than a global: the app seeds it from `WhereSession` (live on store changes),
/// the widget process from its `WidgetSnapshot`, and App Intents snippets from
/// their services. An empty resolver (the environment default) yields the
/// fallback looks — correct for previews, the standalone region-map viewer, and
/// any surface that hasn't been seeded.
public struct RegionStyleResolver: Sendable, Equatable {
    private let appearances: [Region: RegionAppearance]

    /// The empty resolver: every region resolves to its fallback look.
    public static let `default` = RegionStyleResolver(appearances: [:])

    public init(appearances: [Region: RegionAppearance]) {
        self.appearances = appearances
    }

    /// Build from ordered `PrimaryRegion`s, keeping only the ones that carry a
    /// resolved appearance.
    public init(primaryRegions: [PrimaryRegion]) {
        var map: [Region: RegionAppearance] = [:]
        for entry in primaryRegions {
            if let appearance = entry.appearance { map[entry.region] = appearance }
        }
        self.init(appearances: map)
    }

    /// The region's look: its picked appearance if customized, else the stable
    /// fallback (a hand-tuned look for the shipped regions, an id-derived default
    /// otherwise).
    public func style(for region: Region) -> RegionStyle {
        if let appearance = appearances[region] {
            return RegionStyle(appearance)
        }
        return RegionStyle.fallbackStyle(for: region)
    }
}

extension EnvironmentValues {
    /// The active region-style resolver, seeded by `whereBroadwayRoot`. Defaults
    /// to the empty resolver (fallback looks) when nothing seeded it.
    @Entry public var regionStyles: RegionStyleResolver = .default
}
