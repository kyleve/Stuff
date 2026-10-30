import BroadwayUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct AppIconPreviewPanelTests {
    @Test func invertedPreviewDoesNotInheritConcretePageInk() throws {
        let option = try #require(AppIconCatalog.load().first)
        let panel = AppIconPreviewPanel(
            option: option,
            containerSize: CGSize(width: 402, height: 874),
            previewMode: .dark,
            appearanceToggles: 0,
            canApply: true,
            toggleAppearance: {},
            apply: {},
        )
        .frame(width: 402)
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
        .whereBroadwayRoot()
        let expected = ImageRenderer(content: panel)
        let actual = ImageRenderer(content: panel.foregroundStyle(Color.black))
        #expect(try #require(actual.uiImage?.pngData()) == #require(expected.uiImage?.pngData()))
    }

    @Test func previewPaperResolvesInsideItsSelectedMode() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "icon-preview-modes"),
            parent: .standard,
            values: .init(colors: nil, fonts: nil, surfaces: nil),
            appearance: .init(),
            components: .init(),
        )
        document.appearance.appIcon = .init()
        document.appearance.appIcon?.panel = .init()
        document.appearance.appIcon?.panel?.background = .modes(.init(
            light: .rgba(red: 1, green: 1, blue: 1, alpha: 1),
            dark: .rgba(red: 1, green: 0, blue: 0, alpha: 1),
        ))
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        let option = try #require(AppIconCatalog.load().first)
        let host = UIHostingController(rootView: AppIconPreviewPanel(
            option: option,
            containerSize: CGSize(width: 402, height: 874),
            previewMode: .dark,
            appearanceToggles: 0,
            canApply: true,
            toggleAppearance: {},
            apply: {},
        )
        .environment(\.colorScheme, .dark)
        .bMode(.dark)
        .whereBroadwayRoot(themeDocument: theme)
        .environment(\.colorScheme, .light))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }
}
