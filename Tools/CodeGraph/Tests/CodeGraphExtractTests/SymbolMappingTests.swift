@testable import code_graph_extract
import CodeGraphModel
import IndexStoreDB
import Testing

/// `SymbolMapping` is the pure translation from index-store symbol metadata to
/// the graph vocabulary, so it can be exercised with hand-built `Symbol`s
/// without opening a real index store.
struct SymbolMappingTests {
    private func symbol(
        _ name: String,
        _ kind: IndexSymbolKind,
        subKind: IndexSymbolSubKind = .none,
        properties: SymbolProperty = SymbolProperty(),
    ) -> Symbol {
        Symbol(
            usr: "s:\(name)",
            name: name,
            kind: kind,
            subKind: subKind,
            properties: properties,
            language: .swift,
        )
    }

    // MARK: - nodeKind

    @Test func mapsNominalTypeKinds() {
        #expect(SymbolMapping.nodeKind(for: symbol("A", .class)) == .class)
        #expect(SymbolMapping.nodeKind(for: symbol("A", .struct)) == .struct)
        #expect(SymbolMapping.nodeKind(for: symbol("A", .enum)) == .enum)
        #expect(SymbolMapping.nodeKind(for: symbol("A", .protocol)) == .protocol)
        #expect(SymbolMapping.nodeKind(for: symbol("A", .extension)) == .extension)
        // C/C++ unions surface as structs.
        #expect(SymbolMapping.nodeKind(for: symbol("A", .union)) == .struct)
    }

    @Test func mapsMemberAndFreeKinds() {
        #expect(SymbolMapping.nodeKind(for: symbol("f", .function)) == .function)
        #expect(SymbolMapping.nodeKind(for: symbol("m", .instanceMethod)) == .method)
        #expect(SymbolMapping.nodeKind(for: symbol("init", .constructor)) == .initializer)
        #expect(SymbolMapping.nodeKind(for: symbol("p", .instanceProperty)) == .property)
        #expect(SymbolMapping.nodeKind(for: symbol("v", .variable)) == .property)
        #expect(SymbolMapping.nodeKind(for: symbol("c", .enumConstant)) == .enumCase)
    }

    @Test func typealiasSubKindsDisambiguate() {
        #expect(SymbolMapping.nodeKind(for: symbol("T", .typealias)) == .typeAlias)
        #expect(
            SymbolMapping
                .nodeKind(for: symbol("T", .typealias, subKind: .swiftAssociatedType)) ==
                .associatedType,
        )
        // A generic type parameter (`<T>`) is noise, not a node.
        #expect(
            SymbolMapping
                .nodeKind(for: symbol("T", .typealias, subKind: .swiftGenericTypeParam)) == nil,
        )
    }

    @Test func accessorsAreNotNodes() {
        #expect(
            SymbolMapping
                .nodeKind(for: symbol("getter:p", .instanceMethod, subKind: .accessorGetter)) ==
                nil,
        )
        #expect(
            SymbolMapping
                .nodeKind(for: symbol("setter:p", .instanceProperty, subKind: .accessorSetter)) ==
                nil,
        )
    }

    @Test func nonNodeKindsReturnNil() {
        #expect(SymbolMapping.nodeKind(for: symbol("M", .module)) == nil)
        #expect(SymbolMapping.nodeKind(for: symbol("x", .parameter)) == nil)
        #expect(SymbolMapping.nodeKind(for: symbol("Macro", .macro)) == nil)
    }

    @Test func compilerSynthesizedNamesAreFilteredOut() {
        // `$`-projected values, property-wrapper/`@Observable` backing storage,
        // and anonymous decls never begin a user identifier.
        #expect(SymbolMapping.nodeKind(for: symbol("$observation", .variable)) == nil)
        #expect(SymbolMapping.nodeKind(for: symbol("_storage", .instanceProperty)) == nil)
        #expect(SymbolMapping.nodeKind(for: symbol("", .class)) == nil)
        // A normal name with the same kind still maps.
        #expect(SymbolMapping.nodeKind(for: symbol("storage", .instanceProperty)) == .property)
    }

    // MARK: - isType

    @Test func isTypeCoversNominalTypesOnly() {
        for kind in [
            IndexSymbolKind.class,
            .struct,
            .enum,
            .protocol,
            .extension,
            .typealias,
            .union,
        ] {
            #expect(SymbolMapping.isType(kind), "\(kind) should be a type")
        }
        for kind in [
            IndexSymbolKind.function,
            .variable,
            .instanceMethod,
            .constructor,
            .module,
            .enumConstant,
            .parameter,
        ] {
            #expect(!SymbolMapping.isType(kind), "\(kind) should not be a type")
        }
    }

    // MARK: - origin

    @Test func originClassifiesByPath() {
        let repo = "/repo/"
        #expect(
            SymbolMapping.origin(path: "/usr/lib/x.swift", isSystem: true, repoPrefix: repo) ==
                .external,
        )
        #expect(SymbolMapping.origin(path: "", isSystem: false, repoPrefix: repo) == .external)
        #expect(
            SymbolMapping.origin(path: "/elsewhere/x.swift", isSystem: false, repoPrefix: repo) ==
                .external,
        )
        #expect(
            SymbolMapping
                .origin(path: "/repo/Where/Sources/x.swift", isSystem: false, repoPrefix: repo) ==
                .firstParty,
        )
        #expect(
            SymbolMapping
                .origin(
                    path: "/repo/Where/Tests/xTests.swift",
                    isSystem: false,
                    repoPrefix: repo,
                ) ==
                .test,
        )
    }
}
