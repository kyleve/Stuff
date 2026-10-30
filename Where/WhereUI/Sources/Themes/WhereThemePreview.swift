#if DEBUG
    import SwiftUI
    import WhereCore

    /// Uses production cards, background, root injection, and decoration rendering.
    struct WhereThemePreview: View {
        let theme: PreparedWhereThemeDocument
        var body: some View {
            VStack(spacing: 24) {
                RegionSummaryCard(regionDays: .init(region: .california, days: 148), year: 2026)
                RegionSummaryCard(
                    regionDays: .init(region: .europeanUnion, days: 22),
                    variant: .compact,
                    year: 2026,
                )
                Spacer(minLength: 120)
            }
            .padding(24)
            .background {
                LocationsBackground(regions: [.california, .europeanUnion])
                    .whereThemeOverlay(.locationsBackground)
            }
            .whereBroadwayRoot(themeDocument: theme)
        }

        @MainActor
        static func example(_ example: WhereThemeExamples) -> Self {
            do { return try Self(theme: example.prepare()) }
            catch { preconditionFailure("Invalid bundled theme: \(error)") }
        }
    }

    #Preview("Halloween") { WhereThemePreview.example(.halloween) }
    #Preview("Christmas") { WhereThemePreview.example(.christmas) }
#endif
