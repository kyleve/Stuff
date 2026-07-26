@_spi(Testing) import CreditKit
import Foundation
import Testing

struct CreditCatalogTests {
    @Test("loads the bundled manifest")
    func loadsTheBundledManifest() {
        #expect(!CreditCatalog.shared.credits.isEmpty)
    }

    @Test("credits every package a target links")
    func creditsEveryLinkedPackage() {
        let libraries = CreditCatalog.shared.credits(ofKind: .library).map(\.name)
        // The one external package any target links via `.product(name:package:)`.
        // BumperBowling and swift-syntax are resolved for architecture linting
        // and never reach the binary, so they are deliberately absent.
        #expect(libraries == ["ZIPFoundation"])
    }

    @Test("credits the vendored agent skills")
    func creditsTheVendoredAgentSkills() {
        let tools = Set(CreditCatalog.shared.credits(ofKind: .developmentTool).map(\.name))
        #expect(tools == [
            "swift-concurrency-pro",
            "swift-testing-pro",
            "swiftdata-pro",
            "swiftui-pro",
        ])
    }

    @Test("groups libraries ahead of development tools")
    func groupsLibrariesAheadOfDevelopmentTools() {
        let kinds = CreditCatalog.shared.credits.map(\.kind)
        #expect(kinds == kinds.sorted { first, _ in first == .library })
    }

    @Test("decoding rejects a malformed manifest")
    func decodingRejectsAMalformedManifest() {
        let data = Data(#"[{"name": "Nope"}]"#.utf8)
        #expect(throws: (any Error).self) {
            try CreditCatalog.decode(from: data)
        }
    }

    @Test("filters to a single kind")
    func filtersToASingleKind() {
        let catalog = CreditCatalog(credits: [
            .fixture(name: "Linked", kind: .library),
            .fixture(name: "Tool", kind: .developmentTool),
        ])
        #expect(catalog.credits(ofKind: .library).map(\.name) == ["Linked"])
        #expect(catalog.credits(ofKind: .developmentTool).map(\.name) == ["Tool"])
    }
}
