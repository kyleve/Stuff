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
                alternateIconName: nil,
                previewImageName: "AppIconClassic",
            ),
            AppIconOption(
                id: AppIconID("ocean"),
                displayName: "Ocean",
                alternateIconName: "AppIconOcean",
                previewImageName: "AppIconOcean",
            ),
        ]
    }

    @Test func initialSelectionDerivesFromTheLiveIcon() {
        let setter = FakeIconSetter(alternateIconName: "AppIconOcean")
        let model = AppIconModel(options: options(), setter: setter)
        #expect(model.selectedID == AppIconID("ocean"))
    }

    @Test func initialSelectionFallsBackToThePrimary() {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(options: options(), setter: setter)
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func applySetsTheIconAndUpdatesSelection() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(options: options(), setter: setter)

        await model.apply(options()[1])

        #expect(setter.alternateIconName == "AppIconOcean")
        #expect(model.selectedID == AppIconID("ocean"))
        #expect(model.applyError == nil)
    }

    @Test func applyingThePrimaryClearsTheAlternateIcon() async {
        let setter = FakeIconSetter(alternateIconName: "AppIconOcean")
        let model = AppIconModel(options: options(), setter: setter)

        await model.apply(options()[0])

        #expect(setter.alternateIconName == nil)
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func applyIsANoOpWhenAlreadySelected() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        let model = AppIconModel(options: options(), setter: setter)

        await model.apply(options()[0])

        #expect(setter.setCallCount == 0)
    }

    @Test func applySurfacesErrorsAndLeavesSelectionUnchanged() async {
        let setter = FakeIconSetter(alternateIconName: nil)
        setter.errorToThrow = FakeIconError.boom
        let model = AppIconModel(options: options(), setter: setter)

        await model.apply(options()[1])

        #expect(model.selectedID == AppIconID("classic"))
        #expect(model.applyError != nil)
        #expect(model.isShowingError)

        model.isShowingError = false
        #expect(model.applyError == nil)
    }

    @Test func unsupportedDevicesDoNotAttemptAChange() async {
        let setter = FakeIconSetter(supportsAlternateIcons: false, alternateIconName: nil)
        let model = AppIconModel(options: options(), setter: setter)

        await model.apply(options()[1])

        #expect(setter.setCallCount == 0)
        #expect(model.selectedID == AppIconID("classic"))
    }

    @Test func bundledManifestLoadsAndIsConsistent() throws {
        let options = try AppIconCatalog.load()

        #expect(!options.isEmpty)
        #expect(options.contains { $0.id == AppIconID("classic") })
        #expect(options.filter(\.isPrimary).count == 1)

        let ids = options.map(\.id)
        #expect(Set(ids).count == ids.count)
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
