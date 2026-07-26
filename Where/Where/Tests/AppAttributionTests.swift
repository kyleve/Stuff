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
            AppAttribution.current(bundle: .main),
            "the app bundle carries no attribution report — run ./attribution",
        )
    }

    @Test func theAppBundleCarriesAReport() throws {
        #expect(try !report().credits.isEmpty)
    }

    @Test func creditsEveryPackageATargetLinks() throws {
        // The one external package any target links via `.product(name:package:)`.
        // BumperBowling and swift-syntax are resolved for architecture linting
        // and never reach the binary, so they are deliberately absent.
        #expect(try report().credits(ofKind: .library).map(\.name) == ["ZIPFoundation"])
    }

    @Test func creditsTheVendoredAgentSkills() throws {
        let tools = try Set(report().credits(ofKind: .developmentTool).map(\.name))
        #expect(tools == [
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

    @Test func aBundleWithoutAReportReadsAsNone() {
        // Every other bundle in the process — the test bundle itself included —
        // legitimately carries no report, and that must stay a quiet `nil`
        // rather than the fault path.
        #expect(AppAttribution.current(bundle: Bundle(for: BundleMarker.self)) == nil)
    }
}

private final class BundleMarker {}
