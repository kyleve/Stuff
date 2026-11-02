import BroadwayCore
import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct BTraitOverridesSwiftUITests {
    @Test func pairedColorSchemeUpdatesBothEnvironmentsAndPreservesThemes() throws {
        let reads = BTraitOverridesTestSupport.Reads()
        var themes = BThemes()
        themes[BTraitOverridesTestSupport.Theme.self] = .b
        func content(scheme: ColorScheme) -> some View {
            BTraitOverridesTestSupport.Probe(reads: reads)
                .bColorScheme(scheme)
                .broadwayRoot(themes: themes)
                .environment(\.colorScheme, .light)
        }
        let host = UIHostingController(rootView: content(scheme: .dark))
        try show(host) { _ in
            try waitFor { reads.latest?.colorScheme == .dark && reads.latest?.mode == .dark }
            #expect(reads.latest?.theme == .b)
            host.rootView = content(scheme: .light)
            try waitFor { reads.latest?.colorScheme == .light && reads.latest?.mode == .light }
            #expect(reads.latest?.theme == .b)
        }
    }

    @Test func pairedExactSizeUpdatesBothEnvironmentsBelowAnExistingRoot() throws {
        let reads = BTraitOverridesTestSupport.Reads()
        func content(size: DynamicTypeSize) -> some View {
            BTraitOverridesTestSupport.Probe(reads: reads)
                .bDynamicTypeSize(size)
                .broadwayRoot()
                .dynamicTypeSize(.accessibility5)
        }
        let host = UIHostingController(rootView: content(size: .small))
        try show(host) { _ in
            try waitFor {
                reads.latest?.dynamicTypeSize == .small
                    && reads.latest?.contentSizeCategory == .small
            }
            host.rootView = content(size: .accessibility3)
            try waitFor {
                reads.latest?.dynamicTypeSize == .accessibility3
                    && reads.latest?.contentSizeCategory == .accessibilityExtraLarge
            }
            host.rootView = content(size: .large)
            try waitFor {
                reads.latest?.dynamicTypeSize == .large
                    && reads.latest?.contentSizeCategory == .large
            }
        }
    }

    @Test func pairedCapTracksTheNativeSizeAndLimitDespiteAnInheritedBroadwayOverride() throws {
        let reads = BTraitOverridesTestSupport.Reads()
        func content(size: DynamicTypeSize, limit: DynamicTypeSize) -> some View {
            BTraitOverridesTestSupport.Probe(reads: reads)
                .bDynamicTypeSize(upTo: limit)
                .bContentSizeCategory(.accessibilityExtraExtraExtraLarge)
                .broadwayRoot()
                .dynamicTypeSize(size)
        }
        let host = UIHostingController(rootView: content(size: .small, limit: .large))
        try show(host) { _ in
            try waitFor {
                reads.latest?.dynamicTypeSize == .small
                    && reads.latest?.contentSizeCategory == .small
            }
            host.rootView = content(size: .accessibility5, limit: .large)
            try waitFor {
                reads.latest?.dynamicTypeSize == .large
                    && reads.latest?.contentSizeCategory == .large
            }
            host.rootView = content(size: .accessibility5, limit: .accessibility1)
            try waitFor {
                reads.latest?.dynamicTypeSize == .accessibility1
                    && reads.latest?.contentSizeCategory == .accessibilityMedium
            }
            host.rootView = content(size: .medium, limit: .accessibility1)
            try waitFor {
                reads.latest?.dynamicTypeSize == .medium
                    && reads.latest?.contentSizeCategory == .medium
            }
        }
    }
}
