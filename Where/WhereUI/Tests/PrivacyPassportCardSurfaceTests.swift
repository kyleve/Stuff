import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct PrivacyPassportCardSurfaceTests {
    @Test func fixedDarkPaperDoesNotInheritLightPageInk() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "page-ink"),
            parent: .flat,
            values: .init(colors: [.init(id: .init(rawValue: "page.ink"), value: .modes(.init(
                light: .rgba(red: 0, green: 0, blue: 0, alpha: 1),
                dark: .rgba(red: 1, green: 1, blue: 1, alpha: 1),
            )))], fonts: nil, surfaces: nil),
            appearance: .init(),
            components: .init(),
        )
        document.components.sheet = .init()
        document.components.sheet?.foreground = .value(.init(rawValue: "page.ink"))
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        let surface = PrivacyPassportCardSurface(tilt: .preview) {
            VStack {
                Text("Primary")
                Text("Supporting text").foregroundStyle(.whereSecondary)
            }.padding(24)
        }
        let expected = ImageRenderer(content: surface
            .whereBroadwayRoot(themeDocument: theme).environment(\.colorScheme, .light))
        let actual = ImageRenderer(content: surface
            .modifier(WhereComponentTextStyle(role: .sheet))
            .whereBroadwayRoot(themeDocument: theme).environment(\.colorScheme, .light))
        #expect(try #require(actual.uiImage?.pngData()) == #require(expected.uiImage?.pngData()))
    }

    @Test func passportPaperUsesTheSameDarkModeAsItsContent() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "privacy-modes"),
            parent: .flat,
            values: .init(colors: [.init(id: .init(rawValue: "privacy.fill"), value: .modes(.init(
                light: .rgba(red: 1, green: 1, blue: 1, alpha: 1),
                dark: .rgba(red: 1, green: 0, blue: 0, alpha: 1),
            )))], fonts: nil, surfaces: nil),
            appearance: .init(),
            components: .init(),
        )
        document.components.privacy = .init()
        document.components.privacy?.nativeArtwork = []
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        let host =
            UIHostingController(rootView: PrivacyPassportCardSurface(tilt: .preview) { Color.clear }
                .whereBroadwayRoot(themeDocument: theme).environment(\.colorScheme, .light))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }
}
