import BroadwayCore
import BroadwayUI
import PeriscopeCore
@testable import PeriscopeTools
import SwiftUI
import TestHostSupport
import Testing
import UIKit

/// Pins ``PeriscopeStylesheet``'s default tokens, the density subscript, the
/// palette's severity/exit mappings, and the trait-aware derivations (resolved
/// synchronously off a `BContext`). Retuning a token means updating these.
@MainActor
struct PeriscopeStylesheetTests {
    private let style = PeriscopeStylesheet.default

    @Test func comfortableRowDefaults() {
        let row = style.row.comfortable
        #expect(row.verticalPadding == 2)
        #expect(row.lineSpacing == 4)
        #expect(row.headerSpacing == 8)
        #expect(row.messageLineLimit == 3)
        #expect(row.indentStep == 14)
    }

    @Test func compactRowDefaults() {
        let row = style.row.compact
        #expect(row.verticalPadding == 1)
        #expect(row.lineSpacing == 1)
        #expect(row.headerSpacing == 6)
        #expect(row.messageLineLimit == 1)
        #expect(row.indentStep == 12)
    }

    @Test func densitySubscriptResolvesTheMatchingRow() {
        #expect(style.row[.comfortable] == style.row.comfortable)
        #expect(style.row[.compact] == style.row.compact)
        #expect(PeriscopeStylesheet.Density.allCases == [.comfortable, .compact])
    }

    @Test func badgeDefaults() {
        #expect(style.badge.horizontalPadding == 6)
        #expect(style.badge.verticalPadding == 2)
        #expect(style.badge.backgroundOpacity == 0.18)
        #expect(style.badge.inspectPadding == 4)
    }

    @Test func levelTintsFollowTheSeverityBands() {
        let palette = style.palette
        #expect(palette.tint(forLevel: .debug) == .gray)
        #expect(palette.tint(forLevel: .info) == .blue)
        #expect(palette.tint(forLevel: .notice) == .teal)
        #expect(palette.tint(forLevel: .warning) == .yellow)
        #expect(palette.tint(forLevel: .error) == .orange)
        #expect(palette.tint(forLevel: .fault) == .red)
    }

    @Test func customLevelInheritsItsSeverityBandTint() {
        let palette = style.palette
        // A custom level between info (200) and notice (300) sits in the
        // "info" band and inherits its blue.
        let custom = LogLevel(name: "trace", severity: 250, osLogType: .info)
        #expect(palette.tint(forLevel: custom) == .blue)
    }

    @Test func spanExitTints() {
        let palette = style.palette
        #expect(palette.tint(forSpanExit: .success) == .green)
        #expect(palette.tint(forSpanExit: .cancelled) == .gray)
        #expect(palette.tint(forSpanExit: .superseded) == .yellow)
        #expect(palette.tint(forSpanExit: .expired) == .orange)
        #expect(palette.tint(forSpanExit: .failure) == .red)
        #expect(palette.tint(forSpanExit: .orphaned) == .purple)
    }

    @Test func inspectBadgeTint() {
        #expect(style.palette.inspectBadge == .purple)
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

    @Test func densityDisplayNames() {
        #expect(PeriscopeStylesheet.Density.comfortable.displayName == "Comfortable")
        #expect(PeriscopeStylesheet.Density.compact.displayName == "Compact")
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

    @Test func rowDensityDefaultsToComfortable() {
        #expect(EnvironmentValues().logRowDensity == .comfortable)
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
