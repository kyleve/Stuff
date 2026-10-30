@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing

@MainActor
struct PeriscopeToolPresentationTests {
    @Test(arguments: PeriscopeStylesheet.Density.allCases)
    func standaloneToolsUseTheirSuppliedDefaults(density: PeriscopeStylesheet.Density) throws {
        let defaults = try PeriscopeToolPresentationTestSupport.Defaults()
        defer { defaults.cleanup() }
        density.save(to: defaults.value)
        let reads = PeriscopeToolPresentationTestSupport.Reads()
        let host = UIHostingController(rootView:
            PeriscopeToolPresentationTestSupport.Probe(reads: reads)
                .periscopeBroadwayRoot(.inheritedOrSaved(defaults.value)))
        try show(host) { _ in
            try waitFor { reads.density == density }
        }
    }

    @Test func drillInsKeepTheViewersDensityAndFollowItsChanges() throws {
        let fallback = try PeriscopeToolPresentationTestSupport.Defaults()
        defer { fallback.cleanup() }
        PeriscopeStylesheet.Density.compact.save(to: fallback.value)
        let reads = PeriscopeToolPresentationTestSupport.Reads()
        func content(density: PeriscopeStylesheet.Density) -> some View {
            PeriscopeToolPresentationTestSupport.Probe(reads: reads)
                .periscopeBroadwayRoot(.inheritedOrSaved(fallback.value))
                .periscopeBroadwayRoot(.density(density))
        }
        let host = UIHostingController(rootView: content(density: .comfortable))
        try show(host) { _ in
            try waitFor { reads.density == .comfortable }
            #expect(PeriscopeStylesheet.Density.load(from: fallback.value) == .compact)
            host.rootView = content(density: .compact)
            try waitFor { reads.density == .compact }
            host.rootView = content(density: .comfortable)
            try waitFor { reads.density == .comfortable }
        }
    }
}
