import Foundation
import PortholeCore
@testable import PortholeRuntime
import Testing

struct PortholeBuiltinCapabilitiesTests {
    @Test func releasesExactHandlesThroughTheNormalExecutorAndPreservesRetryIdentity() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let reference = try await registry.retain("captured", in: scope, retention: .results)
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.release(.init(id: reference.id, scope: scope, typeName: "WrongType"))
        }
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.objects.release"),
            receiver: nil,
            arguments: .object([
                "objectID": .string(reference.id.uuidString),
                "typeName": .string(reference.typeName),
            ]),
        )
        #expect(try await registry.invoke(invocation) == .null)
        #expect(try await registry.invoke(invocation) == .null)
        #expect(try await registry.objectReferences(in: scope).isEmpty)
        #expect(await registry.pendingApprovals().isEmpty)
        await #expect(throws: PortholeError.unknownObject) { try await registry.resolve(
            reference,
            as: String.self,
            in: scope,
        ) }
    }

    @Test func searchesExactBundledSourceAndRejectsUnboundedPages() async throws {
        let registry = PortholeRegistry(
            journal: PortholeOperationJournal(url: nil),
            objectLimit: 10,
        )
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        await registry.setEnabled(true)
        let source = PortholeSourceFile(
            path: "file.swift",
            content: "one\ntwo needle\nthree needle",
        )
        let archive = try JSONEncoder().encode([source])
        try await registry.installSourceArchive(String(decoding: archive, as: UTF8.self), in: scope)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.source.search"),
            receiver: nil,
            arguments: .object([
                "query": .string("needle"),
                "offset": .integer(1),
                "limit": .integer(1),
            ]),
        )
        let result = try await registry.invoke(invocation)
        #expect(result["total"] == .integer(2))
        #expect(try result["items"] == .array([.object([
            "path": .string("file.swift"),
            "line": .integer(3),
            "text": .string("three needle"),
            "sha256": .string(source.sha256),
            "scope": .encoding(scope),
        ])]))
        let read = try await registry.invoke(PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.source.read"),
            receiver: nil,
            arguments: .object([
                "path": .string(source.path),
                "offset": .integer(1),
                "limit": .integer(1),
            ]),
        ))
        #expect(read["sha256"] == .string(source.sha256))
        #expect(try read["scope"]?.decode(PortholeScopeToken.self) == scope)
        #expect(read["firstLine"] == .integer(2))
        let invalid = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: invocation.capabilityID,
            receiver: nil,
            arguments: .object([
                "query": .string("needle"),
                "offset": .integer(0),
                "limit": .integer(1000),
            ]),
        )
        await #expect(throws: PortholeError.self) { try await registry.invoke(invalid) }
    }

    @Test func rejectsSourcePageWhoseLineNumberWouldOverflow() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let source = PortholeSourceFile(path: "file.swift", content: "one")
        let archive = try JSONEncoder().encode([source])
        try await registry.installSourceArchive(String(decoding: archive, as: UTF8.self), in: scope)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.source.read"),
            receiver: nil,
            arguments: .object([
                "path": .string(source.path),
                "offset": .integer(Int64.max),
                "limit": .integer(1),
            ]),
        )
        await #expect(throws: PortholeError.invalidArguments(
            "offset must be from 0 through \(Int.max - 1); limit must be 1...200",
        )) {
            try await registry.invoke(invocation)
        }
    }

    @Test func rejectsSourceContentThatDoesNotMatchItsBundledHash() async throws {
        let registry = PortholeRegistry(
            journal: PortholeOperationJournal(url: nil),
            objectLimit: 10,
        )
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        await #expect(throws: PortholeError.self) {
            try await registry.installSourceArchive(
                "[{\"path\":\"file.swift\",\"content\":\"modified\",\"sha256\":\"wrong\"}]",
                in: scope,
            )
        }
    }
}

extension PortholeBuiltinCapabilitiesTests {
    @Test func coverageUsesReadCapabilitiesAndRetainsSourceEvidence() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "coverage"))
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        try await PortholeRuntimeCoverageTestSupport.installSources(in: registry, scope: scope)
        let row = PortholeRuntimeCoverageTestSupport.declaration(
            "unsupported",
            availability: .unsupported("Callback isolation is not bound"),
        )
        try await registry.describe(
            PortholeRuntimeCoverageTestSupport
                .capability(row, availability: row.plannedAvailability),
            in: scope,
        )
        try await registry.installCoverage(PortholeRuntimeCoverageTestSupport.json([
            PortholeRuntimeCoverageTestSupport.module([row]),
            PortholeRuntimeCoverageTestSupport.module([], moduleID: .init(rawValue: "NoActiveAPI")),
        ]), in: scope)
        let client = PortholeCoverageClient { try await registry.invoke($0) }
        let modules = try await client.modules(in: scope, offset: 0, limit: 200)
        #expect(modules.items.count == 2)
        #expect(modules.items.last?.counts.total == 0)
        let page = try await client.declarations(
            in: scope,
            query: PortholeRuntimeCoverageTestSupport.query(search: "CALLBACK ISOLATION"),
        )
        #expect(page.scope == scope)
        #expect(page.items.first?.declaration.sourceSHA256 == PortholeRuntimeCoverageTestSupport
            .source.sha256)
        #expect(page.items.first?.state == .unsupported("Callback isolation is not bound"))
        let descriptors = try await registry.capabilities(in: scope).filter {
            $0.id == PortholeCoverageCapabilities.modules || $0.id == PortholeCoverageCapabilities
                .declarations
        }
        #expect(descriptors.count == 2)
        #expect(descriptors.allSatisfy { $0.effect == .read })
        #expect(await registry.pendingApprovals().isEmpty)
        let discover = try await registry.invoke(.init(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.discover"),
            receiver: nil,
            arguments: .object([
                "query": .string("CALLBACK ISOLATION"),
                "offset": .integer(0),
                "limit": .integer(10),
            ]),
        ))
        #expect(discover["total"] == .integer(1))
        #expect(try discover["items"]?.decode([PortholeCapability].self).first?.id == row.id)
        await registry.invalidate(scope)
        await #expect(throws: PortholeError.staleScope) { try await client.modules(
            in: scope,
            offset: 0,
            limit: 1,
        ) }
    }

    @Test func coverageWireRejectsUnboundedAndOverflowingQueries() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "coverage"))
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        for query in [
            PortholeRuntimeCoverageTestSupport.query(offset: Int.max),
            PortholeRuntimeCoverageTestSupport.query(offset: -1),
            PortholeRuntimeCoverageTestSupport.query(limit: 201),
            PortholeRuntimeCoverageTestSupport.query(search: String(repeating: "x", count: 4097)),
        ] {
            let invocation = try PortholeInvocation(
                id: UUID(),
                scope: scope,
                capabilityID: PortholeCoverageCapabilities.declarations,
                receiver: nil,
                arguments: .object(["query": .encoding(query)]),
            )
            await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
        }
        await #expect(throws: PortholeError.self) {
            try await registry.invoke(.init(
                id: UUID(),
                scope: scope,
                capabilityID: PortholeCoverageCapabilities.modules,
                receiver: nil,
                arguments: .object(["offset": .integer(Int64.max), "limit": .integer(1)]),
            ))
        }
        #expect(await registry.pendingApprovals().isEmpty)
    }
}

extension PortholeBuiltinCapabilitiesTests {
    @Test func coverageClientsReportMissingInstallationAndAcceptExplicitEmptyCoverage(
    ) async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "coverage-presence"))
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let client = PortholeCoverageClient { try await registry.invoke($0) }
        let missing = PortholeError
            .operationFailed("Source coverage has not been installed in this scope.")
        await #expect(throws: missing) { try await client.modules(in: scope, offset: 0, limit: 10) }
        await #expect(throws: missing) {
            try await client.declarations(
                in: scope,
                query: PortholeRuntimeCoverageTestSupport.query(),
            )
        }
        try await registry.installCoverage(PortholeRuntimeCoverageTestSupport.json([]), in: scope)
        let modules = try await client.modules(in: scope, offset: 0, limit: 10)
        let declarations = try await client.declarations(
            in: scope,
            query: PortholeRuntimeCoverageTestSupport.query(),
        )
        #expect(modules.total == 0 && modules.items.isEmpty)
        #expect(declarations.total == 0 && declarations.items.isEmpty)
        #expect(await registry.pendingApprovals().isEmpty)
    }
}
