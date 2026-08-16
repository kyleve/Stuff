@testable import SnapshotKit
import SwiftUI
import Testing

/// Pure-logic tests for the ``SnapshotConfiguration`` matrix: combination counts,
/// preset shapes, and the identifier omission rules that name reference images.
struct SnapshotConfigurationTests {
    @Test func emptyCombinationsIsTheDefaultSingleton() {
        let configs = SnapshotConfiguration.combinations()
        #expect(configs == [SnapshotConfiguration()])
    }

    @Test func combinationsAreTheCartesianProduct() {
        let configs = SnapshotConfiguration.combinations(
            colorSchemes: [.light, .dark],
            dynamicTypes: [.large, .accessibility5],
        )
        #expect(configs.count == 4)
    }

    @Test func combinationsMultiplyEveryAxis() {
        let configs = SnapshotConfiguration.combinations(
            devices: [.iPhone, .iPad],
            colorSchemes: [.light, .dark],
            contrasts: [.standard, .increased],
        )
        #expect(configs.count == 8)
    }

    @Test func componentDefaultsAreAdditiveNotCartesian() {
        // baseline + dark + accessibility type size + increased contrast + a11y capture
        #expect([SnapshotConfiguration].componentDefaults.count == 5)
    }

    @Test func screenDefaultsCoverBothDevices() {
        #expect([SnapshotConfiguration].screenDefaults.count == 10)
    }

    @Test func fullContentScreenDefaultsCoverBothDeviceWidths() {
        let configs = [SnapshotConfiguration].fullContentScreenDefaults
        #expect(configs.count == 10)
        #expect(Set(configs.map(\.device.name)) == ["iPhone", "iPad"])
        #expect(configs.allSatisfy { configuration in
            switch configuration.device.size {
                case .fullContent: true
                case .fixed, .intrinsic, .fullContent2D: false
            }
        })
    }

    @Test func fullContentDeviceFramesRetainViewportMinimums() {
        #expect(SnapshotConfiguration.Frame.iPhoneFullContent.size == .fullContent(
            width: 402,
            minimumHeight: 874,
        ))
        #expect(SnapshotConfiguration.Frame.iPadFullContent.size == .fullContent(
            width: 834,
            minimumHeight: 1194,
        ))

        let custom = SnapshotConfiguration.Frame.fullContent(name: "custom", width: 500)
        #expect(custom.size == .fullContent(width: 500, minimumHeight: nil))
    }

    @Test func twoAxisFullContentFramesRetainViewportMinimums() {
        #expect(SnapshotConfiguration.Frame.iPhoneFullContent2D.size == .fullContent2D(
            minimumSize: CGSize(width: 402, height: 874),
        ))
        #expect(SnapshotConfiguration.Frame.iPadFullContent2D.size == .fullContent2D(
            minimumSize: CGSize(width: 834, height: 1194),
        ))

        let custom = SnapshotConfiguration.Frame.fullContent2D(
            name: "spatial",
            minimumSize: CGSize(width: 500, height: 600),
        )
        #expect(custom.size == .fullContent2D(
            minimumSize: CGSize(width: 500, height: 600),
        ))
    }

    @Test func baselineIdentifierIsEmpty() {
        #expect(SnapshotConfiguration().identifier.isEmpty)
    }

    @Test func nonDefaultAxesAppearInTheIdentifier() {
        #expect(SnapshotConfiguration(colorScheme: .dark).identifierParts == ["dark"])
        #expect(SnapshotConfiguration(dynamicType: .accessibility5).identifierParts == ["ax5"])
        #expect(SnapshotConfiguration(contrast: .increased).identifierParts == ["contrast"])
        #expect(SnapshotConfiguration(layoutDirection: .rightToLeft).identifierParts == ["rtl"])
        #expect(SnapshotConfiguration(legibilityWeight: .bold).identifierParts == ["bold"])
        #expect(SnapshotConfiguration(snapshotType: .accessibility)
            .identifierParts == ["accessibility"])
        #expect(SnapshotConfiguration(device: .iPad).identifierParts == ["iPad"])
        #expect(SnapshotConfiguration(device: .iPhoneNotched).identifierParts == ["iPhoneNotched"])
    }

    @Test func identifierOrdersAndJoinsPartsWithNameFirst() {
        let config = SnapshotConfiguration(
            colorScheme: .dark,
            contrast: .increased,
            device: .iPhone,
            name: "empty",
        )
        #expect(config.identifier == "empty_iPhone_dark_contrast")
    }

    @Test func componentFrameHasNoNameSoItStaysOutOfIdentifiers() {
        #expect(SnapshotConfiguration(device: .component).identifierParts.isEmpty)
    }

    @Test func combinationsMultiplyTheDirectionAndWeightAxes() {
        let configs = SnapshotConfiguration.combinations(
            layoutDirections: [.leftToRight, .rightToLeft],
            legibilityWeights: [.regular, .bold],
        )
        #expect(configs.count == 4)
    }

    @Test func framesDefaultToZeroSafeAreaInsets() {
        #expect(SnapshotConfiguration.Frame.iPhone.safeAreaInsets == .zero)
        #expect(SnapshotConfiguration.Frame.iPad.safeAreaInsets == .zero)
        #expect(SnapshotConfiguration.Frame.component.safeAreaInsets == .zero)
    }

    @Test func notchedFrameCarriesDeviceInsets() {
        let frame = SnapshotConfiguration.Frame.iPhoneNotched
        #expect(frame.safeAreaInsets.top == 47)
        #expect(frame.safeAreaInsets.bottom == 34)
        #expect(frame.safeAreaInsets.leading == 0)
        #expect(frame.safeAreaInsets.trailing == 0)
    }
}
