import SwiftUI
import TestHostSupport
import Testing
import WhereCore
@testable import WhereUI

@MainActor
struct WherePresentationContextTests {
    @Test func suppliesAndUpdatesThemeAndRegionLooksTogether() throws {
        let custom = WherePresentationContext(
            theme: .alternate,
            regionStyles: RegionStyleResolver(appearances: [
                .california: RegionAppearance(color: .pink, emoji: "🦋", symbolName: .starFill),
            ]),
        )
        let fallback = WherePresentationContext(theme: .standard, regionStyles: .default)
        let reads = WhereEnvironmentTestSupport.Reads()
        func content(_ presentation: WherePresentationContext) -> some View {
            WhereEnvironmentTestSupport.Probe(reads: reads).whereBroadwayRoot(presentation)
        }
        let host = UIHostingController(rootView: content(custom))
        try show(host) { _ in
            try waitFor { reads.latest?.theme == .alternate }
            #expect(reads.latest?.regionStyles == custom.regionStyles)
            #expect(reads.latest?.regionStyles.style(for: .california).emoji == "🦋")
            let cache = try #require(reads.latest?.cache)
            host.rootView = content(fallback)
            try waitFor { reads.latest?.theme == .standard }
            #expect(reads.latest?.regionStyles == .default)
            #expect(reads.latest?.cache == cache)
        }
    }
}
