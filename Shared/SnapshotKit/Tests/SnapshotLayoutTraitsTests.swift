@testable import SnapshotKit
import SwiftUI
import Testing

struct SnapshotLayoutTraitsTests {
    @Test func namedPresetsKeepTheirIdentifiersAndTruthfulTraits() {
        for frame in [
            SnapshotConfiguration.Frame.iPhone,
            .iPhoneFullContent,
            .iPhoneFullContent2D,
        ] {
            #expect(SnapshotConfiguration(device: frame).identifier == "iPhone")
            #expect(frame.layoutTraits == .phonePortrait)
        }
        for frame in [SnapshotConfiguration.Frame.iPad, .iPadFullContent, .iPadFullContent2D] {
            #expect(SnapshotConfiguration(device: frame).identifier == "iPad")
            #expect(frame.layoutTraits == .tablet)
        }
        #expect(SnapshotConfiguration.Frame.component.layoutTraits == nil)
    }

    @Test func mapsEachLayoutAxisToUIKit() {
        let configuration = SnapshotConfiguration(device: .viewport(
            name: "landscapePhone",
            size: CGSize(width: 640, height: 320),
            layoutTraits: .init(
                horizontalSizeClass: .regular,
                verticalSizeClass: .compact,
                interfaceIdiom: .phone,
            ),
        ))
        #expect(configuration.uiTraitCollection.horizontalSizeClass == .regular)
        #expect(configuration.uiTraitCollection.verticalSizeClass == .compact)
        #expect(configuration.uiTraitCollection.userInterfaceIdiom == .phone)
    }

    @Test func narrowWindowRetainsTabletIdiomWithCompactWidth() {
        let configuration = SnapshotConfiguration(device: .narrowWindow)
        #expect(configuration.uiTraitCollection.horizontalSizeClass == .compact)
        #expect(configuration.uiTraitCollection.verticalSizeClass == .regular)
        #expect(configuration.uiTraitCollection.userInterfaceIdiom == .pad)
    }
}
