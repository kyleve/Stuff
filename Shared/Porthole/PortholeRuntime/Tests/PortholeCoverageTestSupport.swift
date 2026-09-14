import Foundation
import PortholeCore
@testable import PortholeRuntime

/// Coverage fixtures share the same source archive and declaration identities as their descriptors.
enum PortholeRuntimeCoverageTestSupport {
    static let source = PortholeSourceFile(path: "Module/Source.swift", content: "struct Item {}")
    static let moduleID = PortholeModuleID(rawValue: "Module")
    static let scope = PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID())

    static func declaration(
        _ name: String,
        availability: PortholeAvailability = .callable,
        origin: PortholeCoverageOrigin = .generated,
    ) -> PortholeDeclarationCoverage {
        .init(
            id: .init(rawValue: "Module.\(name)"),
            name: name,
            kind: origin == .excludedFile ? .excludedFile : .function,
            signature: "func \(name)(value: Int)",
            source: origin == .excludedFile ? nil : .init(path: source.path, line: 1),
            sourceSHA256: origin == .excludedFile ? nil : source.sha256,
            conditions: ["DEBUG && canImport(Example)"],
            plannedAvailability: availability,
            origin: origin,
        )
    }

    static func module(
        _ declarations: [PortholeDeclarationCoverage],
        moduleID: PortholeModuleID = PortholeRuntimeCoverageTestSupport.moduleID,
    ) -> PortholeModuleCoverage {
        .init(
            module: moduleID,
            build: .init(configuration: "Debug", toolchain: "fixture-compiler"),
            files: [.init(path: source.path, sha256: source.sha256)],
            declarations: declarations,
        )
    }

    static func capability(
        _ declaration: PortholeDeclarationCoverage,
        availability: PortholeAvailability,
        name: String? = nil,
    ) -> PortholeCapability {
        .init(
            id: declaration.id,
            module: moduleID,
            name: name ?? declaration.name,
            summary: "Fixture declaration",
            parameters: [],
            result: .any,
            effect: .unknown,
            source: declaration.source,
            ownership: .adapter,
            availability: availability,
        )
    }

    static func query(
        search: String = "",
        status: PortholeCoverageStatusFilter = .all,
        offset: Int = 0,
        limit: Int = 200,
    ) -> PortholeCoverageQuery {
        .init(module: nil, search: search, status: status, offset: offset, limit: limit)
    }

    static func json(_ modules: [PortholeModuleCoverage], version: Int = 1) throws -> String {
        try String(decoding: JSONEncoder().encode(PortholeCoverageDocument(
            version: version,
            modules: modules,
        )), as: UTF8.self)
    }

    static func installSources(
        in registry: PortholeRegistry,
        scope: PortholeScopeToken,
    ) async throws {
        let json = try String(decoding: JSONEncoder().encode([source]), as: UTF8.self)
        try await registry.installSourceArchive(json, in: scope)
    }

    static func store(
        modules: Int = 10,
        declarations: Int = 100,
        bytes: Int = 100_000,
    ) -> PortholeCoverageStore {
        .init(maximumModules: modules, maximumDeclarations: declarations, maximumBytes: bytes)
    }

    static func install(
        _ modules: [PortholeModuleCoverage],
        in store: inout PortholeCoverageStore,
        scope: PortholeScopeToken = PortholeRuntimeCoverageTestSupport.scope,
        registrations: [PortholeSymbolID: PortholeCoverageStore.Registration] = [:],
    ) throws {
        try store.install(json(modules), in: scope, sources: [source.path: source]) {
            registrations[$0]
        }
    }
}
