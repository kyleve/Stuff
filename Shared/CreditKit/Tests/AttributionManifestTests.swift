import CreditKit
import Foundation
import Testing

/// Covers the manifest as a *format* and an API. Deliberately names no real
/// dependency: which packages an app links is that app's fact to assert, not
/// this library's — see `AppAttributionTests` in the Where app's bundle.
struct AttributionManifestTests {
    // MARK: Decoding the generated shape

    @Test func decodesTheShapeTheReportWrites() throws {
        let manifest = try AttributionManifest.decode(from: Data(SampleReport.json.utf8))

        #expect(manifest.credits.map(\.name) == ["Linked", "Tool"])
        let linked = try #require(manifest.credits.first)
        #expect(linked.kind == .library)
        #expect(linked.version == "0.9.20")
        #expect(linked.homepageURL == URL(string: "https://github.com/example/linked"))
        #expect(linked.license.name == "MIT License")
        #expect(linked.license.text == "Linked notice.")
    }

    @Test func decodingRejectsAMalformedReport() {
        #expect(throws: (any Error).self) {
            try AttributionManifest.decode(from: Data(#"{"credits":[{"name":"Nope"}]}"#.utf8))
        }
    }

    @Test func decodingRejectsAnUnknownKind() {
        // `Kind` is a closed vocabulary: a report naming something else is a
        // generator/runtime mismatch and must fail loudly, not decode to a
        // silent default.
        let json = """
        {"credits":[{"name":"X","kind":"plugin","version":"1",
        "license":{"name":"MIT","text":"t"}}]}
        """
        #expect(throws: (any Error).self) {
            try AttributionManifest.decode(from: Data(json.utf8))
        }
    }

    @Test func decodesAReportWithNoCredits() throws {
        // Structurally valid and distinct from a *missing* report, which is the
        // case a caller is expected to treat differently.
        let manifest = try AttributionManifest.decode(from: Data(#"{"credits":[]}"#.utf8))
        #expect(manifest.credits.isEmpty)
    }

    @Test func aCreditWithoutAHomepageIsAllowed() throws {
        let json = """
        {"credits":[{"name":"X","kind":"library","version":"1",
        "license":{"name":"MIT","text":"t"}}]}
        """
        let manifest = try AttributionManifest.decode(from: Data(json.utf8))
        #expect(try #require(manifest.credits.first).homepageURL == nil)
    }

    // MARK: Round trip

    @Test func survivesAnEncodeDecodeRoundTrip() throws {
        let original = AttributionManifest(credits: [
            .fixture(name: "Linked", kind: .library),
            .fixture(name: "Tool", kind: .developmentTool),
        ])
        let data = try JSONEncoder().encode(original)
        #expect(try AttributionManifest.decode(from: data) == original)
    }

    // MARK: Filtering

    @Test func filtersToASingleKind() {
        let manifest = AttributionManifest(credits: [
            .fixture(name: "Linked", kind: .library),
            .fixture(name: "Tool", kind: .developmentTool),
            .fixture(name: "AlsoLinked", kind: .library),
        ])
        #expect(manifest.credits(ofKind: .library).map(\.name) == ["Linked", "AlsoLinked"])
        #expect(manifest.credits(ofKind: .developmentTool).map(\.name) == ["Tool"])
    }

    @Test func filteringPreservesReportOrder() {
        let names = ["c", "a", "b"]
        let manifest = AttributionManifest(
            credits: names.map { .fixture(name: $0, kind: .library) },
        )
        #expect(manifest.credits(ofKind: .library).map(\.name) == names)
    }

    // MARK: Loading from a bundle

    @Test func loadingThrowsWhenTheBundleCarriesNoReport() {
        #expect(throws: AttributionError.reportMissing(resource: "attribution")) {
            try AttributionManifest.load(from: .main, resource: "attribution")
        }
    }
}
