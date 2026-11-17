import BroadwayCore
import BroadwayUI
import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Covers density persistence and selection, severity/exit mappings, and trait derivation.
@MainActor
struct PeriscopeStylesheetTests {
    private let style = PeriscopeStylesheet.default

    @Test func densitySubscriptResolvesTheMatchingRow() {
        #expect(style.row[.comfortable] == style.row.comfortable)
        #expect(style.row[.compact] == style.row.compact)
    }

    @Test func levelTintsFollowTheSeverityBands() {
        let palette = style.palette
        #expect(palette.tint(forLevel: .debug) == palette.levelDebug)
        #expect(palette.tint(forLevel: .info) == palette.levelInfo)
        #expect(palette.tint(forLevel: .notice) == palette.levelNotice)
        #expect(palette.tint(forLevel: .warning) == palette.levelWarning)
        #expect(palette.tint(forLevel: .error) == palette.levelError)
        #expect(palette.tint(forLevel: .fault) == palette.levelFault)
    }

    @Test func customLevelInheritsItsSeverityBandTint() {
        let palette = style.palette
        // A custom level between info (200) and notice (300) sits in the
        // "info" band and inherits its tint.
        let custom = LogLevel(name: "trace", severity: 250, osLogType: .info)
        #expect(palette.tint(forLevel: custom) == palette.levelInfo)
    }

    @Test func spanExitTints() {
        let palette = style.palette
        #expect(palette.tint(forSpanExit: .success) == palette.spanSuccess)
        #expect(palette.tint(forSpanExit: .cancelled) == palette.spanCancelled)
        #expect(palette.tint(forSpanExit: .superseded) == palette.spanSuperseded)
        #expect(palette.tint(forSpanExit: .expired) == palette.spanExpired)
        #expect(palette.tint(forSpanExit: .failure) == palette.spanFailure)
        #expect(palette.tint(forSpanExit: .orphaned) == palette.spanOrphaned)
    }

    /// With default/system traits the stylesheet resolves to the fixed defaults.
    @Test func resolvesThroughBroadwayToTheDefaults() throws {
        let context = BContext(traits: .system)
        let resolved = try context.stylesheets.get(PeriscopeStylesheet.self)
        #expect(resolved == .default)
    }

    @Test func growsMessageLineLimitAtAccessibilitySizes() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .accessibilityLarge
        let resolved = try context.stylesheets.get(PeriscopeStylesheet.self)
        #expect(resolved.row.comfortable.messageLineLimit == 4)
        #expect(resolved.row.compact.messageLineLimit == 2)
    }

    /// A large but *non-accessibility* size stays on the default line limits —
    /// only accessibility sizes bump them, so this pins the boundary.
    @Test func keepsDefaultLineLimitsBelowAccessibilitySizes() throws {
        var context = BContext(traits: .system)
        context.traitOverrides.contentSizeCategory = .extraExtraExtraLarge
        let resolved = try context.stylesheets.get(PeriscopeStylesheet.self)
        #expect(resolved.row.comfortable.messageLineLimit == style.row.comfortable.messageLineLimit)
        #expect(resolved.row.compact.messageLineLimit == style.row.compact.messageLineLimit)
    }

    @Test func persistedDensityDefaultsToCompactWhenUnset() {
        withEphemeralDefaults { defaults in
            #expect(PeriscopeStylesheet.Density.load(from: defaults) == .compact)
        }
    }

    @Test func persistedDensityRoundTrips() {
        withEphemeralDefaults { defaults in
            PeriscopeStylesheet.Density.comfortable.save(to: defaults)
            #expect(PeriscopeStylesheet.Density.load(from: defaults) == .comfortable)
            PeriscopeStylesheet.Density.compact.save(to: defaults)
            #expect(PeriscopeStylesheet.Density.load(from: defaults) == .compact)
        }
    }

    /// A stored value that no longer maps to a case (an old/corrupt key)
    /// falls back to the default rather than trapping.
    @Test func persistedDensityFallsBackWhenTheStoredValueIsUnknown() {
        withEphemeralDefaults { defaults in
            defaults.set("bogus", forKey: PeriscopeStylesheet.Density.defaultsKey)
            #expect(PeriscopeStylesheet.Density.load(from: defaults) == .compact)
        }
    }

    /// Runs `body` against a throwaway `UserDefaults` suite so the test never
    /// touches the shared standard domain.
    private func withEphemeralDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "periscope.tools.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create an ephemeral UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}

/// Covers the PeriscopeTools glue: `EnvironmentValues.stylesheet` resolves a
/// `PeriscopeStylesheet` from the environment's `\.bContext`, falling back to
/// `default` when no context is set, and `periscopeBroadwayRoot()` seeds a
/// trait-aware context across the PeriscopeTools↔BroadwayUI module boundary.
///
/// The boundary crossing only resolves when both modules share a single
/// BroadwayUI copy — the reason `BroadwayCore`/`BroadwayUI` are dynamic
/// libraries — so this guards the duplicate-copy failure that only surfaces in
/// the full multi-bundle test host.
@MainActor
struct PeriscopeStylesheetEnvironmentTests {
    @Test func fallsBackToDefaultWithoutAContext() {
        #expect(EnvironmentValues().stylesheet == .default)
    }

    @Test func resolvesTraitAwareTokensFromTheBroadwayRoot() async throws {
        let box = StylesheetProbeBox()
        let host = UIHostingController(
            rootView: StylesheetProbe(box: box)
                .bContentSizeCategory(.accessibilityLarge)
                .periscopeBroadwayRoot(),
        )
        try await showHosted(host) { _ in
            #expect(await waitUntil { box.messageLineLimit == 4 })
        }
    }
}

private final class StylesheetProbeBox {
    var messageLineLimit: Int?
}

private struct StylesheetProbe: View {
    let box: StylesheetProbeBox

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Color.clear
            .onChange(
                of: stylesheet.row.comfortable.messageLineLimit,
                initial: true,
            ) { _, newValue in
                box.messageLineLimit = newValue
            }
    }
}
