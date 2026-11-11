@testable import BroadwayCore
import TestHostSupport
import Testing
import UIKit

@MainActor
struct BHorizontalSizeClassTests {
    @Test func mapsUIKitValuesAndDefaultsToCompact() {
        #expect(BHorizontalSizeClass(.unspecified) == .compact)
        #expect(BHorizontalSizeClass(.compact) == .compact)
        #expect(BHorizontalSizeClass(.regular) == .regular)
        #expect(BTraits().horizontalSizeClass == .compact)
        #expect(BTraits.system.horizontalSizeClass == .compact)
    }

    @Test func observesLiveChangesAndScopedOverrides() throws {
        let host = UIViewController()
        host.traitOverrides.horizontalSizeClass = .compact
        try show(host) { controller in
            let observer = BTraitsObserver(traits: .system, from: controller, onChange: { _ in })
            observer.start()
            defer { observer.stop() }
            #expect(observer.traits.horizontalSizeClass == .compact)
            controller.traitOverrides.horizontalSizeClass = .regular
            try waitFor { observer.traits.horizontalSizeClass == .regular }
            var overrides = BTraits.Overrides()
            overrides.horizontalSizeClass = .compact
            #expect(observer.traits.merging(with: overrides).horizontalSizeClass == .compact)
            #expect(observer.traits.horizontalSizeClass == .regular)
        }
    }
}
