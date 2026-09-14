import Foundation
import PortholeCore
@testable import PortholeRuntime
import Testing

struct PortholeCoverageStoreTests {
    private typealias Fixture = PortholeRuntimeCoverageTestSupport

    @Test func distinguishesMissingCoverageFromAnExplicitEmptyDocument() throws {
        var store = Fixture.store()
        let missing = PortholeError
            .operationFailed("Source coverage has not been installed in this scope.")
        #expect(throws: missing) {
            try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }
        }
        #expect(throws: missing) {
            try store.declarations(in: Fixture.scope, query: Fixture.query()) { _ in nil }
        }
        #expect(throws: PortholeError.self) {
            try store.install(
                Fixture.json([Fixture.module([Fixture.declaration("missingSource")])]),
                in: Fixture.scope,
                sources: [:],
            ) { _ in nil }
        }
        #expect(throws: missing) {
            try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }
        }
        try Fixture.install([], in: &store)
        let modules = try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }
        let declarations = try store
            .declarations(in: Fixture.scope, query: Fixture.query()) { _ in nil }
        #expect(modules.total == 0)
        #expect(modules.items.isEmpty)
        #expect(declarations.total == 0)
        #expect(declarations.items.isEmpty)
        store.invalidate(Fixture.scope)
        #expect(throws: missing) {
            try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }
        }
    }

    @Test func resolvesCompiledStateWithoutTurningPlannerSupportIntoExecution() throws {
        let callable = Fixture.declaration("callable", availability: .unsupported("Planner reason"))
        let described = Fixture.declaration("described")
        let metadata = Fixture.declaration("metadata", availability: .inspectable)
        let unsupported = Fixture.declaration("unsupported")
        let inactive = Fixture.declaration("inactive")
        let sourceOnly = Fixture.declaration(
            "sourceOnly",
            availability: .unsupported("Native module policy"),
            origin: .sourceOnly,
        )
        let excluded = Fixture.declaration(
            "excluded",
            availability: .unsupported("Credential source policy"),
            origin: .excludedFile,
        )
        let registrations: [PortholeSymbolID: PortholeCoverageStore.Registration] = [
            callable.id: .init(
                capability: Fixture.capability(callable, availability: .callable),
                hasHandler: true,
            ),
            described.id: .init(
                capability: Fixture.capability(described, availability: .callable),
                hasHandler: false,
            ),
            metadata.id: .init(
                capability: Fixture.capability(metadata, availability: .inspectable),
                hasHandler: false,
            ),
            unsupported.id: .init(
                capability: Fixture
                    .capability(
                        unsupported,
                        availability: .unsupported("Final unsupported signature"),
                    ),
                hasHandler: false,
            ),
        ]
        var store = Fixture.store()
        try Fixture.install([
            Fixture.module([
                callable,
                described,
                metadata,
                unsupported,
                inactive,
                sourceOnly,
                excluded,
            ]),
            Fixture.module([], moduleID: .init(rawValue: "ZeroActive")),
        ], in: &store, registrations: registrations)
        let page = try store
            .declarations(in: Fixture.scope, query: Fixture.query()) { registrations[$0] }
        #expect(page.scope == Fixture.scope)
        #expect(page.total == 7)
        let rows = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
        #expect(rows[callable.id]?.state == .callable)
        #expect(rows[callable.id]?.declaration
            .plannedAvailability == .unsupported("Planner reason"))
        #expect(rows[described.id]?.state == .inspectableSource)
        #expect(rows[metadata.id]?.state == .inspectableSource)
        #expect(rows[unsupported.id]?.state == .unsupported("Final unsupported signature"))
        #expect(rows[inactive.id]?.state == .inactive)
        #expect(rows[inactive.id]?.installedCapabilityID == nil)
        #expect(rows[sourceOnly.id]?.state == .sourceOnly("Native module policy"))
        #expect(rows[excluded.id]?.state == .excluded("Credential source policy"))
        let modules = try store
            .modules(in: Fixture.scope, offset: 0, limit: 200) { registrations[$0] }
        #expect(modules.items.map(\.module.rawValue) == ["Module", "ZeroActive"])
        #expect(modules.items[0].counts == .init(
            total: 7,
            callable: 1,
            inspectableSource: 2,
            unsupported: 1,
            inactive: 1,
            sourceOnly: 1,
            excluded: 1,
        ))
        #expect(modules.items[1].counts.total == 0)
        for search in [
            "PLANNER REASON",
            "final unsupported",
            "Native module policy",
            "credential source",
        ] {
            #expect(try store
                .declarations(in: Fixture.scope, query: Fixture.query(search: search)) {
                    registrations[$0]
                }.total == 1)
        }
        #expect(try store.declarations(
            in: Fixture.scope,
            query: Fixture.query(search: "canImport(Example)", status: .inactive),
        ) { registrations[$0] }.items.map(\.id) == [inactive.id])
        #expect(try store.declarations(
            in: Fixture.scope,
            query: Fixture.query(search: "value: Int", offset: 3, limit: 2),
        ) { registrations[$0] }.items.count == 2)
    }

    @Test func rejectsConflictsAtomicallyAndAcceptsIdenticalInstallation() throws {
        let row = Fixture.declaration("one")
        let module = Fixture.module([row])
        var store = Fixture.store()
        try Fixture.install([module], in: &store)
        try Fixture.install([module], in: &store)
        #expect(try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }.total == 1)
        #expect(throws: PortholeError.self) {
            try Fixture.install([
                Fixture.module([], moduleID: .init(rawValue: "WouldBePartial")),
                Fixture.module([Fixture.declaration("different")]),
            ], in: &store)
        }
        #expect(try store.modules(in: Fixture.scope, offset: 0, limit: 10) { _ in nil }.total == 1)
        #expect(throws: PortholeError.self) { try Fixture.install([module, module], in: &store) }
        #expect(throws: PortholeError.self) { try Fixture.install(
            [Fixture.module([row, row])],
            in: &store,
        ) }
        #expect(throws: PortholeError.self) {
            try Fixture.install(
                [Fixture.module([row], moduleID: .init(rawValue: "Other"))],
                in: &store,
            )
        }
        #expect(throws: PortholeError.self) {
            try store.install(
                Fixture.json([module], version: 2),
                in: Fixture.scope,
                sources: [Fixture.source.path: Fixture.source],
            ) { _ in nil }
        }
        #expect(throws: PortholeError.self) {
            var fresh = Fixture.store()
            try fresh.install(Fixture.json([module]), in: Fixture.scope, sources: [:]) { _ in nil }
        }
    }

    @Test func validatesExistingAndFutureRegistrationsAndSourceOnlyPolicy() throws {
        let row = Fixture.declaration("one")
        var store = Fixture.store()
        let mismatch = Fixture.capability(row, availability: .callable, name: "Different name")
        #expect(throws: PortholeError.self) {
            try Fixture.install(
                [Fixture.module([row])],
                in: &store,
                registrations: [row.id: .init(capability: mismatch, hasHandler: true)],
            )
        }
        try Fixture.install([Fixture.module([row])], in: &store)
        #expect(throws: PortholeError.self) { try store.validate(
            mismatch,
            hasHandler: true,
            in: Fixture.scope,
        ) }
        let sourceOnly = Fixture.declaration(
            "sourceOnly",
            availability: .unsupported("Native module policy"),
            origin: .sourceOnly,
        )
        var native = Fixture.store()
        try Fixture.install([Fixture.module([sourceOnly])], in: &native)
        #expect(throws: PortholeError.self) {
            try native.validate(
                Fixture.capability(sourceOnly, availability: .callable),
                hasHandler: true,
                in: Fixture.scope,
            )
        }
        #expect(throws: PortholeError.self) {
            var invalid = Fixture.store()
            try Fixture.install(
                [Fixture.module([Fixture.declaration("missingReason", origin: .sourceOnly)])],
                in: &invalid,
            )
        }
    }

    @Test func boundsAggregateRetentionAndReleasesInvalidatedScopes() throws {
        let module = Fixture.module([Fixture.declaration("one")])
        let otherScope = PortholeScopeToken(id: .init(rawValue: "other"), generation: UUID())
        var store = Fixture.store(modules: 1, declarations: 1)
        try Fixture.install([module], in: &store)
        #expect(throws: PortholeError.self) { try Fixture.install(
            [module],
            in: &store,
            scope: otherScope,
        ) }
        store.invalidate(Fixture.scope)
        try Fixture.install([module], in: &store, scope: otherScope)
        #expect(try store.modules(in: otherScope, offset: 0, limit: 1) { _ in nil }.total == 1)
        var declarations = Fixture.store(declarations: 1)
        #expect(throws: PortholeError.self) { try Fixture.install(
            [Fixture.module([Fixture.declaration("one"), Fixture.declaration("two")])],
            in: &declarations,
        ) }
        let documentBytes = try Fixture.json([module]).utf8.count
        var bytes = Fixture.store(bytes: documentBytes)
        try Fixture.install([module], in: &bytes)
        #expect(throws: PortholeError.self) { try Fixture.install(
            [module],
            in: &bytes,
            scope: otherScope,
        ) }
        var tiny = Fixture.store(bytes: 10)
        #expect(throws: PortholeError.self) { try Fixture.install([module], in: &tiny) }
    }

    @Test func rejectsInvalidQueriesWithoutOverflowAndReturnsExactTotals() throws {
        var store = Fixture.store()
        try Fixture.install(
            [Fixture.module([Fixture.declaration("one"), Fixture.declaration("two")])],
            in: &store,
        )
        for query in [
            Fixture.query(offset: -1),
            Fixture.query(offset: Int.max),
            Fixture.query(limit: 0),
            Fixture.query(limit: 201),
            Fixture.query(search: String(repeating: "a", count: 4097)),
        ] {
            #expect(throws: PortholeError.self) { try store.declarations(
                in: Fixture.scope,
                query: query,
            ) { _ in nil } }
        }
        let page = try store.declarations(
            in: Fixture.scope,
            query: Fixture.query(offset: Int.max - 1),
        ) { _ in nil }
        #expect(page.total == 2)
        #expect(page.items.isEmpty)
        #expect(throws: PortholeError.self) { try store.modules(
            in: Fixture.scope,
            offset: Int.max,
            limit: 1,
        ) { _ in nil } }
    }
}
