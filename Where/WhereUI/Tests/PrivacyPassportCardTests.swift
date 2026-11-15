import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct PrivacyPassportCardTests {
    @Test func typographyAndLayoutResolveInsideTheDarkPassportBoundary() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "privacy-layout"),
            parent: .flat,
            values: .init(
                colors: nil,
                fonts: [.init(id: .init(rawValue: "privacy-body"), value: .modes(.init(
                    light: .init(size: .semantic(.caption2), weight: nil, design: nil),
                    dark: .init(size: .semantic(.title), weight: nil, design: nil),
                )))],
                surfaces: nil,
            ),
            appearance: .init(),
            components: .init(),
        )
        document.components.privacy = .init()
        document.components.privacy?.body = .value(.init(rawValue: "privacy-body"))
        document.appearance.privacyPassportCard = .init()
        document.appearance.privacyPassportCard?.padding = .modes(.init(light: 4, dark: 30))
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        func size(_ mode: ColorScheme) throws -> CGSize {
            let card = PrivacyPassportCard(
                presentation: .init(configuration: .defaults(isDebugBuild: false)),
                disclosureInteraction: .staticContent,
            )
            .frame(width: 360)
            .whereBroadwayRoot(themeDocument: theme)
            .environment(\.colorScheme, mode)
            return try #require(ImageRenderer(content: card).uiImage).size
        }
        #expect(try size(.light) == size(.dark))
    }

    @Test func hosts() throws {
        let rootView = PrivacyPassportCard(presentation: PrivacyPassportPresentation(
            configuration: .defaults(isDebugBuild: false),
        ), disclosureInteraction: .linkToSettings)
            .whereBroadwayRoot()
        try show(UIHostingController(rootView: rootView)) { hosted in
            #expect(hosted.view != nil)
        }
    }
}
