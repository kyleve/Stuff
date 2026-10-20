import Testing
@testable import ViewLayoutDiscovery

struct DiscoveryTests {
    @Test func preservesConditionalPrivateAndGenericDeclarations() throws {
        let declarations = try discoverViews(source: """
        #if DEBUG
        private struct Outer<T> {
            struct Inner: SwiftUI.View { var body: some View { fatalError() } }
        }
        #elseif os(macOS)
        struct Desktop: View {}
        #else
        struct Mobile: View {}
        #endif
        """, path: "Fixture.swift")
        #expect(declarations.map(\.name) == ["Outer", "Outer.Inner", "Desktop", "Mobile"])
        #expect(declarations[1].generic)
        #expect(declarations[1].bases == ["View"])
        #expect(declarations[1].condition == "(DEBUG)")
        #expect(declarations[2].condition == "!(DEBUG) && (os(macOS))")
        #expect(declarations[3].condition == "!(DEBUG) && !(os(macOS))")
    }

    @Test func inventoriesProtocolsAndExtensionConformances() throws {
        let declarations = try discoverViews(source: """
        protocol Pane: View {}
        struct Settings: Pane {}
        struct Sample {}
        extension Sample: View {}
        """, path: "Fixture.swift")
        #expect(declarations[0].kind == "protocol")
        #expect(declarations[0].generic)
        #expect(declarations[1].bases == ["Pane"])
        #expect(declarations[3].name == "Sample")
        #expect(declarations[3].kind == "extension")
    }

    @Test func inventoriesAliasesWithoutPretendingToResolveTheirLayouts() throws {
        let declarations = try discoverViews(source: """
        typealias Concrete = GenericCard<Text>
        typealias Qualified = SwiftUI.Text
        """, path: "Fixture.swift")
        #expect(declarations[0].kind == "typealias")
        #expect(declarations[0].bases == ["GenericCard"])
        #expect(declarations[1].bases == ["Text"])
    }

    @Test func rejectsBrokenSource() {
        #expect(throws: (any Error).self) {
            try discoverViews(source: "struct Broken: View {", path: "Broken.swift")
        }
    }
}
