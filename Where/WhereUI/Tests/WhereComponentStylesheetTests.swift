import BroadwayCore
import SwiftUI
import Testing
import ViewDocumentCore
@testable import WhereUI

@MainActor
struct WhereComponentStylesheetTests {
    @Test func authoredPointSizesStillScaleForNativeDynamicType() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "scaled-font"),
            parent: .standard,
            values: .init(
                colors: nil,
                fonts: [.init(
                    id: .init(rawValue: "point-size"),
                    value: .constant(.init(size: .fixed(18), weight: .regular, design: .rounded)),
                )],
                surfaces: nil,
            ),
            appearance: .init(),
            components: .init(),
        )
        document.components.welcome = .init()
        document.components.welcome?.heading = .value(.init(rawValue: "point-size"))
        document.components.welcome?.body = .value(.init(rawValue: "point-size"))
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        var themes = BThemes()
        themes[WhereDocumentTheme.self] = .init(document: theme.validated)
        var traits = BTraits()
        let normal = try BContext(traits: traits, themes: themes).stylesheets
            .get(WhereComponentStylesheet.self)
        traits.contentSizeCategory = .accessibilityExtraExtraExtraLarge
        let large = try BContext(traits: traits, themes: themes).stylesheets
            .get(WhereComponentStylesheet.self)
        #expect(normal[.welcome].heading != large[.welcome].heading)
        #expect(normal[.welcome].body != large[.welcome].body)
    }

    @Test(arguments: WhereThemeExamples.allCases)
    func accessibilityKeepsEssentialSurfacesAndBoundsOptionalArtwork(
        example: WhereThemeExamples,
    ) throws {
        let prepared = try example.prepare()
        var themes = BThemes()
        themes[WhereDocumentTheme.self] = .init(document: prepared.validated)
        var traits = BTraits()
        let regular = try BContext(traits: traits, themes: themes).stylesheets
            .get(WhereComponentStylesheet.self)
        #expect(regular[.locations].background != nil)
        #expect(regular[.welcome].secondaryForeground == regular[.welcome].foreground?
            .opacity(0.85))
        #expect(!regular[.regularCard].artworkOpacity.isEmpty)
        #expect(regular[.regularCard].outsets.bottom == (example == .halloween ? 70 : 60))
        traits.accessibility = .init(
            isDarkerSystemColorsEnabled: true,
            isReduceTransparencyEnabled: true,
        )
        let accessible = try BContext(traits: traits, themes: themes).stylesheets
            .get(WhereComponentStylesheet.self)
        #expect(accessible[.locations].background == regular[.locations].background)
        #expect(accessible[.welcome].secondaryForeground == accessible[.welcome].foreground?
            .opacity(1))
        #expect(Set(accessible[.regularCard].artworkOpacity.keys) ==
            [.init(rawValue: example == .halloween ? "edge" : "gildedEdge")])
        #expect(accessible[.regularCard].outsets == EdgeInsets())
        guard case let .matte(paper) = accessible[.calendarMonth].surface else {
            Issue.record("Essential paper surface disappeared")
            return
        }
        #expect(paper.outline.width >= 1.5)
        #expect(paper.outline.opacity >= 0.65)
    }
}
