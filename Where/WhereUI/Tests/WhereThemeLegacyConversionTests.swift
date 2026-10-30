import BroadwayCore
import Foundation
import Testing
import ViewDocumentCore
@testable import WhereUI

struct WhereThemeLegacyConversionTests {
    @Test @MainActor func legacyFixturesConvertPrepareAndEncodeOnlyVersionTwo() throws {
        for fixture in LegacyThemeFixtures.Theme.allCases {
            let prepared = try LegacyThemeFixtures.prepare(fixture)
            #expect(prepared.validated.document.schemaVersion == 2)
            #expect(prepared.componentArtwork.values.contains { !$0.isEmpty })
            let data = try JSONEncoder().encode(prepared.validated.document)
            let roundTrip = try JSONDecoder().decode(WhereThemeDocument.self, from: data)
            #expect(roundTrip == prepared.validated.document)
            #expect(roundTrip.layers == .init())
        }
    }

    @Test func legacyMatteEnablesNeutralPaperButVersionTwoRequiresCompletePaper() throws {
        let data = Data(
            #"{"schemaVersion":1,"id":"legacy","fallback":"standard","appearance":{"card":{"regular":{"surface":{"constant":{"_0":{"matte":{"_0":{"outline":{"width":2}}}}}}}}},"layers":{}}"#
                .utf8,
        )
        let imported = try JSONDecoder().decode(WhereThemeDocument.self, from: data)
        #expect(imported.schemaVersion == 2)
        let resolved = try WhereThemeCatalog(documents: WhereBundledThemeDefinitions.documents
            .get() + [imported]).resolve(imported.id)
        guard case let .matte(paper) = resolved.appearance.card?.regular?.surface?
            .resolve(mode: .light)
        else {
            Issue.record("Expected imported matte surface")
            return
        }
        #expect(paper.outline?.width == 2)
        #expect(paper.fill?.tintMix == 0)
        #expect(paper.shadow?.radius == 0)
        var strict = imported
        strict.id = .init(rawValue: "strict")
        strict.appearance.card?.regular?.surface = .constant(.matte(.init(
            fill: nil,
            outline: .init(opacity: nil, width: 2),
            shadow: nil,
            pressedTintOpacity: nil,
        )))
        #expect(throws: WhereThemeValidationError.self) {
            try WhereThemeCatalog(documents: WhereBundledThemeDefinitions.documents
                .get() + [strict]).resolve(strict.id)
        }
    }

    @Test func legacyOptionalPartsReceiveTheirOldDefaults() throws {
        let data = Data(
            #"{"schemaVersion":1,"id":"optional","fallback":"standard","appearance":{"card":{"compact":{"paper":{"value":{"_0":{}}},"entryStamp":{"arc":{"value":{"_0":{"opacity":{"constant":{"_0":0.4}}}}}},"regionShape":{"value":{"_0":{"watermark":{"stroke":{"value":{"_0":{"opacity":{"constant":{"_0":0.8}}}}}}}}}}}},"layers":{}}"#
                .utf8,
        )
        let imported = try JSONDecoder().decode(WhereThemeDocument.self, from: data)
        let resolved = try WhereThemeCatalog(documents: WhereBundledThemeDefinitions.documents
            .get() + [imported]).resolve(imported.id)
        try resolved.appearance.requireComplete(path: "appearance")
        guard case let .value(paper) = resolved.appearance.card?.compact?.paper else {
            Issue.record("Expected enabled paper")
            return
        }
        #expect(paper.surface?.resolve(mode: .dark).fill?.base?.resolve(mode: .dark) == .rgba(
            red: 1,
            green: 1,
            blue: 1,
            alpha: 1,
        ))
        #expect(paper.contentTint?.resolve(mode: .dark).color?.resolve(mode: .dark) == .rgba(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1,
        ))

        #expect(try JSONDecoder().decode(
            WhereThemeDocument.self,
            from: JSONEncoder().encode(imported),
        ) == imported)
    }

    @Test @MainActor func legacySlotCapacitySurvivesConversion() throws {
        func layer(_ index: Int) -> ViewDocument {
            .init(
                schemaVersion: 1,
                root: .init(
                    id: .init(rawValue: "layer-\(index)"),
                    content: .shape(.rectangle),
                    modifiers: [],
                    animation: nil,
                    accessibility: .hidden,
                ),
            )
        }
        var document = themeDocument(appearance: .init(), fallback: .flat)
        document.layers.regularCardBackground = (0 ..< 8).map(layer)
        document.layers.regularCardOverlay = (8 ..< 16).map(layer)
        let validated = try ValidatedWhereThemeDocument(
            document: document,
            resources: .init(images: [], symbols: []),
        )
        #expect(validated.artwork[.regularCard]?.count == 16)
        document.layers.regularCardBackground?.append(layer(16))
        #expect(throws: WhereThemeValidationError.self) {
            try ValidatedWhereThemeDocument(
                document: document,
                resources: .init(images: [], symbols: []),
            )
        }
    }
}
