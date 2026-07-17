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
