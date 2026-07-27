import CreditKit
import Foundation
import Testing
import WhereCore

/// Covers the Where app's *own* attribution report, which is why it lives here
/// rather than in `CreditKitTests`: this bundle is hosted by `Where.app`, so
/// `Bundle.main` is the shipping bundle, and a generic attribution library has
/// no business asserting which packages its consumer links.
///
/// These are the drift guard. `./attribution` regenerates the report, but
/// nothing forces it to be re-run, so a dependency added without regenerating
/// fails here rather than silently shipping an incomplete About screen.
@MainActor
struct AppAttributionTests {
    private func report() throws -> AttributionManifest {
        try #require(
            AppAttribution.main,
            "the app bundle carries no attribution report — run ./attribution",
        )
    }

    @Test func theAppBundleCarriesAReport() throws {
        #expect(try !report().credits.isEmpty)
    }

    @Test func creditsEveryPackageTheAppShips() throws {
        // The one external package inside the app's target closure. BumperBowling
        // and swift-syntax are resolved for architecture linting and never linked
        // at all, so they are deliberately absent.
        #expect(try report().credits(ofKind: .library).map(\.name) == ["ZIPFoundation"])
    }

    @Test func creditsWhatTheRepoUsesWithoutShipping() throws {
        let tools = try Set(report().credits(ofKind: .developmentTool).map(\.name))
        #expect(tools == [
            // Linked only by the test-support target, so credited but not in the
            // binary — listing these as libraries would misdescribe the app.
            "AccessibilitySnapshot",
            "swift-snapshot-testing",
            // Vendored into the repo by ./sync-agents.
            "swift-concurrency-pro",
            "swift-testing-pro",
            "swiftdata-pro",
            "swiftui-pro",
        ])
    }

    @Test func everyCreditCarriesItsNoticeInline() throws {
        for credit in try report().credits {
            #expect(!credit.license.text.isEmpty, "\(credit.name) ships no license notice")
            #expect(!credit.license.name.isEmpty, "\(credit.name) names no license")
            #expect(!credit.version.isEmpty, "\(credit.name) records no version")
            #expect(credit.homepageURL != nil, "\(credit.name) records no homepage")
        }
    }

    @Test func namesEveryCreditUniquely() throws {
        // `SoftwareCredit` is `Identifiable` by name, so a collision would hand
        // the About screen's `ForEach` two rows sharing one id. `./attribution`
        // refuses to write a report with duplicates; this catches one edited in
        // by hand, and names the offenders rather than just counting them.
        let names = try report().credits.map(\.name)
        let collisions = Dictionary(grouping: names) { $0.lowercased() }
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        #expect(
            collisions.isEmpty,
            "duplicate credit name(s): \(collisions.joined(separator: ", "))",
        )
    }

    @Test func cachesTheReportItReadsFromTheMainBundle() {
        // `AppAttribution.main` is what the About screen's default argument
        // reads on every view init, so the cached value has to answer exactly
        // what a fresh read of the same bundle would.
        #expect(AppAttribution.main == AppAttribution.current(bundle: .main))
    }

    @Test func aBundleWithoutAReportReadsAsNone() {
        // Every other bundle in the process — the test bundle itself included —
        // legitimately carries no report, and that must stay a quiet `nil`
        // rather than the fault path.
        #expect(AppAttribution.current(bundle: Bundle(for: BundleMarker.self)) == nil)
    }
}

private final class BundleMarker {}
