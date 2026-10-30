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

    @Test func combinationsMultiplyAdaptiveLayoutTraits() {
        let configs = SnapshotConfiguration.combinations(
            devices: [.iPhone, .iPad],
            layoutTraits: [.phonePortrait, .tabletPortrait],
        )

        #expect(configs.count == 4)
        #expect(Set(configs.compactMap(\.layoutTraits)) == [.phonePortrait, .tabletPortrait])
    }

    @Test func componentRepresentativeAreAdditiveNotCartesian() {
        // baseline + dark + accessibility type size + increased contrast + a11y capture
        #expect([SnapshotConfiguration].componentRepresentative.count == 5)
    }

    @Test func screenRepresentativeCoverBothDevices() {
        #expect([SnapshotConfiguration].screenRepresentative.count == 10)
    }

    @Test func representativePresetsPreserveReferenceIdentifiersAndOrdering() {
        #expect([SnapshotConfiguration].componentRepresentative.map(\.identifier) == [
            "",
            "dark",
            "ax5",
            "contrast",
            "accessibility",
        ])
        let screenIdentifiers = [
            "iPhone",
            "iPad",
            "iPhone_dark",
            "iPad_dark",
            "iPhone_ax5",
            "iPad_ax5",
            "iPhone_contrast",
            "iPad_contrast",
            "iPhone_accessibility",
            "iPad_accessibility",
        ]
        #expect([SnapshotConfiguration].screenRepresentative.map(\.identifier) == screenIdentifiers)
        #expect([SnapshotConfiguration].fullContentScreenRepresentative
            .map(\.identifier) == screenIdentifiers)
    }

    @Test func additionalStatePresetsOnlyVaryAppearanceAndPreserveSizing() {
        #expect([SnapshotConfiguration].componentLightDark == [
            SnapshotConfiguration(),
            SnapshotConfiguration(colorScheme: .dark),
        ])
        #expect([SnapshotConfiguration].phoneLightDark == [
            SnapshotConfiguration(device: .iPhone),
            SnapshotConfiguration(colorScheme: .dark, device: .iPhone),
        ])
        #expect([SnapshotConfiguration].fullContentPhoneLightDark == [
            SnapshotConfiguration(device: .iPhoneFullContent),
            SnapshotConfiguration(colorScheme: .dark, device: .iPhoneFullContent),
        ])
    }

    @Test func focusedPhoneAX5PresetPreservesConfigurationsAndReferenceOrder() {
        let configurations = [SnapshotConfiguration].fullContentPhoneLightDarkWithAX5
        #expect(configurations == [
            SnapshotConfiguration(device: .iPhoneFullContent),
            SnapshotConfiguration(colorScheme: .dark, device: .iPhoneFullContent),
            SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhoneFullContent),
        ])
        #expect(configurations.map(\.identifier) == ["iPhone", "iPhone_dark", "iPhone_ax5"])
    }

    @Test func focusedPhoneAnnotationPresetPreservesConfigurationsAndReferenceOrder() {
        let configurations = [SnapshotConfiguration].fullContentPhoneLightDarkWithAnnotations
        #expect(configurations == [
            SnapshotConfiguration(device: .iPhoneFullContent),
            SnapshotConfiguration(colorScheme: .dark, device: .iPhoneFullContent),
            SnapshotConfiguration(device: .iPhoneFullContent, snapshotType: .accessibility),
        ])
        #expect(configurations.map(\.identifier) == [
            "iPhone",
            "iPhone_dark",
            "iPhone_accessibility",
        ])
    }

    @Test func focusedPhoneAX5AndAnnotationPresetKeepsTheAxesSeparate() {
        let configurations = [SnapshotConfiguration].fullContentPhoneLightDarkWithAX5AndAnnotations
        #expect(configurations == [
            SnapshotConfiguration(device: .iPhoneFullContent),
            SnapshotConfiguration(colorScheme: .dark, device: .iPhoneFullContent),
            SnapshotConfiguration(dynamicType: .accessibility5, device: .iPhoneFullContent),
            SnapshotConfiguration(device: .iPhoneFullContent, snapshotType: .accessibility),
        ])
        #expect(configurations.map(\.identifier) == [
            "iPhone",
            "iPhone_dark",
            "iPhone_ax5",
            "iPhone_accessibility",
        ])
    }

    @Test func focusedComponentAnnotationPresetPreservesConfigurationsAndReferenceOrder() {
        let configurations = [SnapshotConfiguration].componentLightDarkWithAnnotations
        #expect(configurations == [
            SnapshotConfiguration(),
            SnapshotConfiguration(colorScheme: .dark),
            SnapshotConfiguration(snapshotType: .accessibility),
        ])
        #expect(configurations.map(\.identifier) == ["", "dark", "accessibility"])
    }

    @Test func fullContentScreenRepresentativeCoverBothDeviceWidths() {
        let configs = [SnapshotConfiguration].fullContentScreenRepresentative
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

    @Test func adaptiveLayoutTraitsHaveStableDistinctIdentifierTokens() {
        let phonePortrait = SnapshotConfiguration(layoutTraits: .phonePortrait)
        let phoneLandscape = SnapshotConfiguration(layoutTraits: .phoneLandscape)
        let tabletPortrait = SnapshotConfiguration(layoutTraits: .tabletPortrait)

        #expect(phonePortrait.identifierParts == ["phone-compact-regular"])
        #expect(phoneLandscape.identifierParts == ["phone-compact-compact"])
        #expect(tabletPortrait.identifierParts == ["tablet-regular-regular"])
        #expect(Set([
            phonePortrait.identifier,
            phoneLandscape.identifier,
            tabletPortrait.identifier,
        ])
        .count == 3)
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
