@testable import BroadwayCore
import TestHostSupport
import Testing
import UIKit

@MainActor
struct BVerticalSizeClassTests {
    @Test func mapsUIKitValuesAndPreservesUnspecified() {
        #expect(BVerticalSizeClass(.unspecified) == .unspecified)
        #expect(BVerticalSizeClass(.compact) == .compact)
        #expect(BVerticalSizeClass(.regular) == .regular)
    }

    @Test func observesLiveChangesAndScopedOverrides() throws {
        let host = UIViewController()
        host.traitOverrides.verticalSizeClass = .compact
        try show(host) { controller in
            let observer = BTraitsObserver(traits: .system, from: controller, onChange: { _ in })
            observer.start()
            defer { observer.stop() }
            #expect(observer.traits.verticalSizeClass == .compact)
            controller.traitOverrides.verticalSizeClass = .regular
            try waitFor { observer.traits.verticalSizeClass == .regular }
            var overrides = BTraits.Overrides()
            overrides.verticalSizeClass = .compact
            #expect(observer.traits.merging(with: overrides).verticalSizeClass == .compact)
            #expect(observer.traits.verticalSizeClass == .regular)
        }
    }
}
