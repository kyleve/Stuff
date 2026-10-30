import SwiftUI
import TestHostSupport
import Testing
import UIKit
@testable import WhereUI

@MainActor
struct FeatureLockScreenExampleTests {
    @Test func wallpaperUsesTheSameDarkModeAsItsContent() throws {
        var document = WhereThemeDocument(
            id: .init(rawValue: "lock-preview-modes"),
            parent: .standard,
            values: .init(colors: nil, fonts: nil, surfaces: nil),
            appearance: .init(),
            components: .init(),
        )
        document.appearance.featureDiscovery = .init()
        document.appearance.featureDiscovery?.widgets = .init()
        document.appearance.featureDiscovery?.widgets?.wallpapers = .init()
        document.appearance.featureDiscovery?.widgets?.wallpapers?.lock = .init()
        document.appearance.featureDiscovery?.widgets?.wallpapers?.lock?.top = .modes(.init(
            light: .rgba(red: 1, green: 1, blue: 1, alpha: 1),
            dark: .rgba(red: 1, green: 0, blue: 0, alpha: 1),
        ))
        let top = document.appearance.featureDiscovery?.widgets?.wallpapers?.lock?.top
        document.appearance.featureDiscovery?.widgets?.wallpapers?.lock?.bottom = top
        let theme = try WhereThemeCatalog(documents: WhereBundledThemes.documents
            .get() + [document])
            .prepare(document.id, assets: .init(images: [:], symbols: [:]))
        let host = UIHostingController(rootView: FeatureLockScreenExample(
            date: PreviewSupport.referenceNow,
            snapshot: PreviewSupport.sampleWidgetSnapshot(),
        )
        .whereBroadwayRoot(themeDocument: theme)
        .environment(\.colorScheme, .light))
        try show(host) { host in
            try waitFor { themeBackgroundIsRed(in: host.view) }
        }
    }
}
