@testable import SnapshotKit
import Testing

struct SnapshotDuoFramesTests {
    @Test(arguments: [
        SnapshotConfiguration.Frame.duoOuterPortrait,
        .duoOuterLandscape,
        .duoInnerPortrait,
        .duoInnerLandscape,
    ])
    func duoViewportsRetainPhoneIdiomAndIndependentInsets(_ frame: SnapshotConfiguration.Frame) {
        let configuration = SnapshotConfiguration(device: frame)
        #expect(configuration.uiTraitCollection.userInterfaceIdiom == .phone)
        guard case let .fixed(size) = frame.size else {
            Issue.record("Duo shell coverage must use a bounded viewport.")
            return
        }
        let insets = frame.safeAreaInsets.uiEdgeInsets
        #expect(size.width > insets.left + insets.right)
        #expect(size.height > insets.top + insets.bottom)
        #expect(insets.left == 0)
        #expect(insets.top > 0 || insets.right > 0)

        var rtl = configuration
        rtl.layoutDirection = .rightToLeft
        #expect(rtl.device.safeAreaInsets.uiEdgeInsets == insets)
    }

    @Test func openingChangesSizeClassesWithoutChangingIdiom() {
        let outer = SnapshotConfiguration(device: .duoOuterLandscape).uiTraitCollection
        let inner = SnapshotConfiguration(device: .duoInnerLandscape).uiTraitCollection
        #expect(outer.horizontalSizeClass == .compact)
        #expect(outer.verticalSizeClass == .compact)
        #expect(inner.horizontalSizeClass == .regular)
        #expect(inner.verticalSizeClass == .regular)
        #expect(inner.userInterfaceIdiom == outer.userInterfaceIdiom)
    }
}
