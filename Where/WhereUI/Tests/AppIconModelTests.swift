import Foundation
import Testing
@testable import WhereUI

@MainActor
struct AppIconModelTests {
    private func options() -> [AppIconOption] {
        [
            AppIconOption(
                id: AppIconID("classic"),
                displayName: "Classic",
                assetName: "AppIcon",
                previewImageName: "AppIconClassic",
            ),
            AppIconOption(
                id: AppIconID("ocean"),
                displayName: "Ocean",
                assetName: "AppIconOcean",
                previewImageName: "AppIconOcean",
            ),
        ]
    }

    @Test func initialSelectionDerivesFromTheLiveIcon() {
        let setter = FakeIconSetter(alternateIconName: "AppIconOcean")
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )
        #expect(model.selectedID == AppIconID("ocean"))
    }

    @Test func initialSelectionFallsBackToThePrimary() {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func nilLiveNameResolvesToANonClassicBuildPrimary() {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIconOcean",
            options: options(),
            setter: setter,
        )

        #expect(model.selectedID == AppIconID("ocean"))
    }

    @Test func selectedOptionMatchesTheLiveAlternateName() {
        let selected = AppIconCatalog.selectedOption(
            in: options(),
            current: "AppIconOcean",
            primaryAppIconName: "AppIcon",
        )
        #expect(selected?.id == AppIconID("ocean"))
    }

    @Test func selectedOptionFallsBackToThePrimaryWhenNil() {
        let selected = AppIconCatalog.selectedOption(
            in: options(),
            current: nil,
            primaryAppIconName: "AppIcon",
        )
        #expect(selected?.id == AppIconID("classic"))
    }

    @Test func selectedOptionFallsBackToThePrimaryForAnUnknownName() {
        // An alternate icon set by an older build but since dropped from the
        // manifest resolves to the primary rather than nothing.
        let selected = AppIconCatalog.selectedOption(
            in: options(),
            current: "AppIconGone",
            primaryAppIconName: "AppIcon",
        )
        #expect(selected?.id == AppIconID("classic"))
    }

    @Test func applySetsTheIconAndUpdatesSelection() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[1])

        #expect(setter.alternateIconName == "AppIconOcean")
        #expect(model.selectedID == AppIconID("ocean"))
        #expect(model.applyError == nil)
    }

    @Test func applyingThePrimaryClearsTheAlternateIcon() async {
        let setter = FakeIconSetter(alternateIconName: "AppIconOcean")
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[0])

        #expect(setter.alternateIconName == nil)
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func classicIsAnAlternateWhenAnotherAssetIsPrimary() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIconOcean",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[0])

        #expect(setter.alternateIconName == "AppIcon")
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func applyIsANoOpWhenAlreadySelected() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[0])

        #expect(setter.setCallCount == 0)
    }

    @Test func applySurfacesErrorsAndLeavesSelectionUnchanged() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        setter.errorToThrow = FakeIconError.boom
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[1])

        #expect(model.selectedID == AppIconID("classic"))
        #expect(model.applyError != nil)
        #expect(model.isShowingError)

        model.isShowingError = false
        #expect(model.applyError == nil)
    }

    @Test func unsupportedDevicesDoNotAttemptAChange() async {
        let setter = FakeIconSetter(supportsAlternateIcons: false, alternateIconName: nil)
        let model = AppIconModel(
            primaryAppIconName: "AppIcon",
            options: options(),
            setter: setter,
        )

        await model.apply(options()[1])

        #expect(setter.setCallCount == 0)
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func bundledManifestLoadsAndIsConsistent() throws {
        let options = try AppIconCatalog.load()

        #expect(options.isEmpty == false)
        #expect(options.contains { $0.id == AppIconID("classic") })
        #expect(options.contains { $0.assetName == "AppIcon" })

        let ids = options.map(\.id)
        #expect(Set(ids).count == ids.count)
        let assetNames = options.map(\.assetName)
        #expect(Set(assetNames).count == assetNames.count)
    }

    /// Guards the core manifest-driven invariant: every option the picker lists
    /// must have matching preview art bundled in WhereUI, or the grid/preview
    /// renders blank. (The app-target appiconsets live outside this test host,
    /// so their existence is covered by the app build / CI, not here.)
    @Test func everyOptionHasBundledPreviewArt() throws {
        let options = try AppIconCatalog.load()

        for option in options {
            #expect(
                AppIconCatalog.previewImageExists(named: option.previewImageName),
                "missing preview art \"\(option.previewImageName)\" for id \"\(option.id.rawValue)\"",
            )
        }
    }
}

private enum FakeIconError: Error {
    case boom
}

@MainActor
private final class FakeIconSetter: AlternateIconSetting {
    var supportsAlternateIcons: Bool
    private(set) var alternateIconName: String?
    var errorToThrow: (any Error)?
    private(set) var setCallCount = 0

    init(supportsAlternateIcons: Bool = true, alternateIconName: String? = nil) {
        self.supportsAlternateIcons = supportsAlternateIcons
        self.alternateIconName = alternateIconName
    }

    func setAlternateIconName(_ alternateIconName: String?) async throws {
        setCallCount += 1
        if let errorToThrow {
            throw errorToThrow
        }
        self.alternateIconName = alternateIconName
    }
}
