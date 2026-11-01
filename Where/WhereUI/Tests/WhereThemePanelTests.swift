import SwiftUI
import TestHostSupport
import Testing
import UIKit
import ViewDocumentCore
import ViewDocumentUI
@testable import WhereUI

@MainActor
struct WhereThemePanelTests {
    @Test func backgroundAndTypographyApplyWithoutSurfaceOrArtwork() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "paint-and-type"),
            parent: .standard,
            values: .init(
                colors: [.init(
                    id: .init(rawValue: "red"),
                    value: .constant(.rgba(red: 1, green: 0, blue: 0, alpha: 1)),
                )],
                fonts: [.init(
                    id: .init(rawValue: "title"),
                    value: .constant(.init(size: .semantic(.title), weight: nil, design: nil)),
                )],
                surfaces: nil,
            ),
            appearance: .init(),
            components: .init(),
        )
        document.components.calendarMonth = .init()
        document.components.calendarMonth?.background = .value(.init(rawValue: "red"))
        document.components.calendarMonth?.body = .value(.init(rawValue: "title"))
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        var observedFont: Font?
        let host = UIHostingController(rootView: FontProbe { observedFont = $0 }
            .whereThemePanel(.calendarMonth, in: Rectangle())
            .whereBroadwayRoot(themeDocument: theme))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) && observedFont == .title }
        }
    }

    @Test func artworkCanInheritTheNativeSurfaceWithoutReplacingIt() throws {
        let existing = try activeThemeBackground()
        var document = existing.validated.document
        document.id = .init(rawValue: "art-only")
        document.components.calendarMonth = .init()
        document.components.calendarMonth?.artwork = existing.resolved.components.locations?.artwork
        document.components.calendarMonth?.artwork?[0].document.root.animation = nil
        let assets = ViewDocumentAssets(images: [:], symbols: [:])
        let prepared = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: assets)
        let host = UIHostingController(rootView: Color.clear
            .whereThemePanel(.calendarMonth, in: Rectangle(), tint: .primary) { Color.white }
            .whereBroadwayRoot(themeDocument: prepared))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }
}

private struct FontProbe: View {
    let observed: (Font?) -> Void
    @Environment(\.font) private var font
    var body: some View {
        Color.clear.onAppear { observed(font) }
    }
}
