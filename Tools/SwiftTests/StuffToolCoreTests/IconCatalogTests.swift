import Foundation
import StuffToolCore
import Testing

struct IconCatalogTests {
    @Test func rendererMatchesTheLegacyManifestAndContentsBytes() throws {
        let planner = IconCatalogPlanner()
        let renderer = IconCatalogRenderer()
        let manifestData = try fixtureData("app-icons", extension: "json")
        let manifest = try planner.decodeManifest(
            manifestData,
            pathDescription: "AppIcons.json",
        )

        #expect(try renderer.manifestData(manifest) == manifestData)
        #expect(try renderer.appContentsData(
            setName: "AppIconPride",
            hasDark: true,
            hasTinted: false,
        ) == fixtureData("app-icon-contents", extension: "json"))
        #expect(try renderer.previewContentsData(
            setName: "AppIconPride",
            hasDark: true,
        ) == fixtureData("app-icon-preview-contents", extension: "json"))
    }

    @Test func additionDerivesNamesAndBuildsACompleteInMemoryPlan() throws {
        let planner = IconCatalogPlanner()
        let manifest = try planner.decodeManifest(
            fixtureData("app-icons", extension: "json"),
            pathDescription: "AppIcons.json",
        )
        let image = try IconImageData(
            data: pngFixtureData(),
            pathDescription: "ocean-sunset.png",
        )

        let addition = try planner.addition(
            manifest: manifest,
            light: image,
            lightFilename: "art/ocean-sunset.png",
            name: nil,
            id: nil,
            dark: image,
            tinted: image,
        )

        #expect(addition.setName == "AppIconOceanSunset")
        #expect(addition.icon == AppIconDescriptor(
            id: "oceansunset",
            displayName: "OceanSunset",
            alternateIconName: "AppIconOceanSunset",
            previewImageName: "AppIconOceanSunset",
        ))
        #expect(addition.manifest.icons.last == addition.icon)
        #expect(addition.dark == image)
        #expect(addition.tinted == image)
    }

    @Test func rejectsInvalidImagesReservedNamesAndDuplicates() throws {
        #expect(throws: IconCatalogFailure.self) {
            _ = try IconImageData(data: Data("not png".utf8), pathDescription: "bad")
        }
        #expect(throws: IconCatalogFailure.self) {
            _ = try IconImageData(
                data: pngFixtureData(width: 512),
                pathDescription: "small.png",
            )
        }

        let planner = IconCatalogPlanner()
        let manifest = try planner.decodeManifest(
            fixtureData("app-icons", extension: "json"),
            pathDescription: "AppIcons.json",
        )
        let image = try IconImageData(
            data: pngFixtureData(),
            pathDescription: "icon.png",
        )
        #expect(throws: IconCatalogFailure.self) {
            _ = try planner.addition(
                manifest: manifest,
                light: image,
                lightFilename: "icon.png",
                name: "Classic",
                id: "classic",
                dark: nil,
                tinted: nil,
            )
        }
        #expect(throws: IconCatalogFailure.self) {
            _ = try planner.addition(
                manifest: manifest,
                light: image,
                lightFilename: "icon.png",
                name: "Another Pride",
                id: "pride",
                dark: nil,
                tinted: nil,
            )
        }
    }

    @Test func removalMatchesCaseInsensitivelyButProtectsThePrimaryIcon() throws {
        let planner = IconCatalogPlanner()
        let manifest = try planner.decodeManifest(
            fixtureData("app-icons", extension: "json"),
            pathDescription: "AppIcons.json",
        )

        let removal = try planner.removal(manifest: manifest, target: "APPICONPRIDE")
        #expect(removal.icon.id == "pride")
        #expect(removal.manifest.icons.map(\.id) == ["classic"])
        #expect(throws: IconCatalogFailure.self) {
            _ = try planner.removal(manifest: manifest, target: "Classic")
        }
        #expect(throws: IconCatalogFailure.self) {
            _ = try planner.removal(manifest: manifest, target: "unknown")
        }
    }
}
