import BroadwayCore
@_spi(Testing) @testable import InstallerKitUI
import SwiftUI
import TestHostSupport
import Testing
import UIKit

@MainActor
struct InstallerStylesheetTests {
    @Test func standardLayoutAndRootlessFallback() throws {
        #expect(EnvironmentValues().installerStylesheet == .default)
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .large
        let style = try context.stylesheets.get(InstallerStylesheet.self)
        #expect(style == .default)
        #expect(style.hero.arrangement == .horizontal)
        #expect(style.summary.columns == .adaptive)
        #expect(style.page.maximumWidth == 760)
        #expect(style.page.padding == 20)
        #expect(style.card.cornerRadius == 24)
        #expect(style.hero.actionMinimumHeight >= 44)
        #expect(style.check.minimumHeight >= 44)
        #expect(style.changes.minimumHeight >= 44)
        #expect(style.browser.minimumHeight >= 44)
    }

    @Test func accessibilityLayoutStartsAtTheSystemBoundary() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .extraExtraExtraLarge
        let standard = try context.stylesheets.get(InstallerStylesheet.self)
        #expect(standard.hero.arrangement == .horizontal)
        #expect(standard.summary.columns == .adaptive)

        context.traitOverrides.contentSizeCategory = .accessibilityMedium
        let accessible = try context.stylesheets.get(InstallerStylesheet.self)
        #expect(accessible.hero.arrangement == .stacked)
        #expect(accessible.details.arrangement == .stacked)
        #expect(accessible.summary.columns == .single)
        #expect(accessible.hero.iconSize == BScaledDimension.value(
            100,
            relativeTo: .title2,
            category: .accessibilityMedium,
        ))
    }

    @Test func publicScreenSeedsItsRootAndRespondsToLiveTraitChanges() throws {
        let probe = InstallerStyleProbeBox()
        let host = UIHostingController(rootView: AppUpdatesView(
            model: InstallerPreview.model(.available),
            branding: InstallerPreview.branding,
            sectionDecoration: { _ in InstallerStyleProbe(box: probe) },
        ))
        host.traitOverrides.preferredContentSizeCategory = .large
        try show(host) { _ in
            try waitFor { probe.style?.hero.arrangement == .horizontal }
            host.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
            try waitFor { probe.style?.hero.arrangement == .stacked }
            #expect(probe.style?.summary.columns == .single)
            host.traitOverrides.preferredContentSizeCategory = .large
            try waitFor { probe.style?.hero.arrangement == .horizontal }
        }
    }
}
