import CreditKit
import Foundation
import Testing
import WhereCore

/// Covers the Where app's *own* attribution report, which is why it lives here
/// rather than in `CreditKitTests`: this bundle is hosted by `Where.app`, so
/// `Bundle.main` is the shipping bundle, and a generic attribution library has
/// no business asserting which packages its consumer links.
///
/// These assert the report is *usable* — present, decodable, and complete
/// enough to render. They deliberately do **not** assert which packages it
/// names: this bundle can't read `Package.swift`, so any such assertion is a
/// literal that a stale report agrees with just as happily as a fresh one. That
/// is not hypothetical — a hardcoded list here passed while the committed report
/// was missing two packages a merge had added. `./attribution --check` owns
/// agreement with the dependency graph and gates CI; this owns everything only
/// the shipping bundle can answer.
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

    @Test func creditsBothKindsOfWork() throws {
        // Not a list of names — that's `--check`'s job. This pins the shape the
        // About screen depends on: two populated sections, so neither renders
        // its "nothing to credit" state in the shipping app.
        for kind in SoftwareCredit.Kind.allCases {
            #expect(
                try !report().credits(ofKind: kind).isEmpty,
                "the report credits nothing of kind \(kind)",
            )
        }
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
