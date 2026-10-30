import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
@testable import WhereUI

@MainActor
struct ValidatedWhereThemeDocumentTests {
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
