@testable import SnapshotKit
import SwiftUI
import Testing
import UIKit

@MainActor
struct SnapshotTraitsTests {
    @Test func removesDeviceOverridesWhenAReusedHostReturnsToInheritedTraits() {
        let host = UIHostingController(rootView: EmptyView())
        applySnapshotTraitOverrides(
            SnapshotConfiguration(
                contrast: .increased,
                layoutTraits: .tabletPortrait,
            ),
            to: host,
        )

        #expect(host.traitCollection.accessibilityContrast == .high)
        #expect(host.traitCollection.userInterfaceIdiom == .pad)
        #expect(host.traitCollection.horizontalSizeClass == .regular)
        #expect(host.traitCollection.verticalSizeClass == .regular)
        #expect(host.traitOverrides.contains(UITraitUserInterfaceIdiom.self))
        #expect(host.traitOverrides.contains(UITraitHorizontalSizeClass.self))
        #expect(host.traitOverrides.contains(UITraitVerticalSizeClass.self))

        applySnapshotTraitOverrides(
            SnapshotConfiguration(contrast: .increased),
            to: host,
        )

        #expect(host.traitCollection.accessibilityContrast == .high)
        #expect(host.traitOverrides.contains(UITraitUserInterfaceIdiom.self) == false)
        #expect(host.traitOverrides.contains(UITraitHorizontalSizeClass.self) == false)
        #expect(host.traitOverrides.contains(UITraitVerticalSizeClass.self) == false)
    }
}
