import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
@testable import WhereUI

@MainActor
struct ValidatedWhereThemeDocumentTests {
    @Test func modifierBudgetIsSharedAcrossSlots() throws {
        let modifiers: [ViewModifierDescriptor] = Array(repeating: .opacity(1), count: 32)
        let layer = ViewDocument(schemaVersion: 1, root: .init(
            id: .init(rawValue: "root"),
            content: .group(
                axis: .overlay,
                alignment: .center,
                spacing: 0,
                children: (0 ..< 31).map {
                    .init(
                        id: .init(rawValue: "child-\($0)"),
                        content: .text(""),
                        modifiers: modifiers,
                        animation: nil,
                        accessibility: .hidden,
                    )
                },
            ),
            modifiers: modifiers,
            animation: nil,
            accessibility: .hidden,
        ))
        let resources = ViewDocumentResources(images: [], symbols: [])
        var document = themeDocument(appearance: .init(), fallback: .standard)
        document.layers.locationsBackground = [layer]
        _ = try ValidatedWhereThemeDocument(document: document, resources: resources)
        document.layers.regularCardOverlay = [layer]
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument(document: document, resources: resources)
        }
    }

    @Test func rejectsUnsafePatternsThroughJSONImport() throws {
        for patch in [
            #"{"featureDiscovery":{"backgroundPattern":{"horizontalScale":{"constant":{"_0":0}}}}}"#,
            #"{"locationForecast":{"surface":{"microprintSpacing":{"constant":{"_0":1e-300}}}}}"#,
            #"{"locationsBackground":{"preferredCellSize":{"constant":{"_0":2}}}}"#,
            #"{"card":{"regular":{"sheen":{"intensity":{"constant":{"_0":42}}}}}}"#,
            #"{"card":{"regular":{"sheen":{"staticGlintIntensity":{"constant":{"_0":42}}}}}}"#,
            #"{"privacyPassportCard":{"reflectiveSurface":{"intensity":{"constant":{"_0":42}}}}}"#,
            #"{"privacyPassportCard":{"reflectiveSurface":{"staticGlintIntensity":{"constant":{"_0":42}}}}}"#,
            #"{"card":{"rosetteFill":{"primary":{"constant":{"_0":42}}}}}"#,
            #"{"card":{"rosetteFill":{"secondary":{"constant":{"_0":42}}}}}"#,
            #"{"card":{"constellation":{"coreWhiteMix":{"constant":{"_0":42}}}}}"#,
            #"{"card":{"securityPrint":{"whiteMix":{"constant":{"_0":42}}}}}"#,
            #"{"developerOverlay":{"menu":{"motion":{"stagger":{"constant":{"_0":10000}}}}}}"#,
            #"{"passportSeal":{"dashSpacing":{"constant":{"_0":-1}}}}"#,
        ] {
            let json =
                "{\"schemaVersion\":1,\"id\":\"unsafe\",\"fallback\":\"standard\",\"appearance\":" +
                patch + ",\"layers\":{}}"
            #expect(throws: WhereThemeValidationError.self) {
                try ValidatedWhereThemeDocument.decode(
                    Data(json.utf8),
                    resources: .init(images: [], symbols: []),
                )
            }
        }
    }

    @Test func layerBudgetIsSharedAcrossSlots() throws {
        let layer = ViewDocument(schemaVersion: 1, root: .init(
            id: .init(rawValue: "root"),
            content: .group(
                axis: .overlay,
                alignment: .center,
                spacing: 0,
                children: (0 ..< 128).map {
                    .init(
                        id: .init(rawValue: "child-\($0)"),
                        content: .text(""),
                        modifiers: [],
                        animation: nil,
                        accessibility: .hidden,
                    )
                },
            ),
            modifiers: [],
            animation: nil,
            accessibility: .hidden,
        ))
        let resources = ViewDocumentResources(images: [], symbols: [])
        _ = try ValidatedViewDocument(document: layer, resources: resources, limits: .standard)
        var document = themeDocument(appearance: .init(), fallback: .standard)
        document.layers.locationsBackground = [layer]
        _ = try ValidatedWhereThemeDocument(document: document, resources: resources)
        document.layers.regularCardOverlay = [layer]
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument(document: document, resources: resources)
        }
    }

    @Test func rejectsInvalidInactiveModeBeforeSelection() throws {
        var appearance = WhereThemeAppearance()
        appearance.flightStatus = .init()
        appearance.flightStatus?.padding = .modes(.init(light: 8, dark: -20))
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument(
                document: themeDocument(appearance: appearance, fallback: .standard),
                resources: .init(images: [], symbols: []),
            )
        }
    }

    @Test func rejectsVersionAndPayloadBeforeRendering() throws {
        var document = themeDocument(appearance: .init(), fallback: .standard)
        document.schemaVersion = 2
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument(
                document: document,
                resources: .init(images: [], symbols: []),
            )
        }
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument.decode(
                Data(repeating: 0, count: ViewDocumentLimits.standard.bytes + 1),
                resources: .init(images: [], symbols: []),
            )
        }
    }

    @Test func accessibilityWinsOverCustomMotionAndGlow() throws {
        var appearance = WhereThemeAppearance()
        appearance.card = .init()
        appearance.card?.regular = .init()
        appearance.card?.regular?.glow = .init()
        appearance.card?.regular?.glow?.radius = .constant(20)
        appearance.launch = .init()
        appearance.launch?.reveal = .constant(.zoom)
        var traits = BTraits.system
        traits.accessibility = .init(isReduceMotionEnabled: true, isReduceTransparencyEnabled: true)
        let resolved = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .standard),
            traits: traits,
        )
        #expect(resolved.card.regular.glow.radius == 0)
        #expect(resolved.launch.reveal == .crossfade)
    }

    @Test func clearDiffersFromInheritanceAndArraysReplace() throws {
        var appearance = WhereThemeAppearance()
        appearance.card = .init()
        appearance.card?.regular = .init()
        appearance.card?.regular?.regionShape = .clear
        appearance.card?.estimateSticker = .init()
        appearance.card?.estimateSticker?.innerDash = .constant([])
        let resolved = try resolveTheme(
            themeDocument(appearance: appearance, fallback: .standard),
            traits: .system,
        )
        #expect(resolved.card.regular.regionShape == nil)
        #expect(resolved.card.compact.regionShape != nil)
        #expect(resolved.card.estimateSticker.innerDash.isEmpty)
    }
}
