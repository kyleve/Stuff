@testable import BroadwayCore
import TestHostSupport
import Testing
import UIKit

@MainActor
struct BHorizontalSizeClassTests {
    @Test func mapsUIKitValuesAndPreservesUnspecified() {
        #expect(BHorizontalSizeClass(.unspecified) == .unspecified)
        #expect(BHorizontalSizeClass(.compact) == .compact)
        #expect(BHorizontalSizeClass(.regular) == .regular)
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
