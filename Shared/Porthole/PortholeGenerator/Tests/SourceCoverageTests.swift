import Foundation
@testable import PortholeGenerator
import Testing

struct SourceCoverageTests {
    @Test func enumInspectionCoverageIsSeparateFromConstructorsAndKeepsRejections() throws {
        let file = SourceFile(path: "Fixture.swift", content: """
        #if DEBUG
        enum State { case empty, loaded(Int) }
        #endif
        enum Unsafe { case pointer(UnsafeRawPointer) }
        """)
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [file])
        let document = try SourceCoverage(
            planner: .init(module: module, dependencyModules: []),
            inventories: [],
        )
        let rows = try #require(document.modules.first).declarations
        let inspector = try #require(rows.first { $0.name == "State.$inspect" })
        #expect(inspector.kind == "enumerationInspection")
        #expect(inspector.origin == .generated)
        #expect(inspector.plannedAvailability == .callable)
        #expect(!inspector.conditions.isEmpty && inspector.sourceSHA256 == file.sha256)
        #expect(rows
            .count(where: { $0.name.hasPrefix("State.") && $0.kind == "enumerationCase" }) == 2)
        let unsupported = try #require(rows.first { $0.name == "Unsafe.$inspect" })
        guard case let .unsupported(reason) = unsupported.plannedAvailability else {
            Issue.record("Unsafe enum inspection lost its rejection"); return
        }
        #expect(reason.contains("pointer") && reason.contains("UnsafeRawPointer"))
        let native = try SourceCoverage(
            planner: .init(
                module: SourceScanner().scan(moduleName: "Empty", files: []),
                dependencyModules: [],
            ),
            inventories: [.init(module: module, reason: "Native boundary", excludedFiles: [])],
        )
        let nativeInspector = try #require(native.modules.last?.declarations
            .first { $0.name == "State.$inspect" })
        #expect(nativeInspector.origin == .sourceOnly)
        #expect(nativeInspector.plannedAvailability == .unsupported("Native boundary"))
    }

    @Test func coverageIdentifiersUseTheRuntimeSingleStringWireShape() throws {
        let module = try SourceScanner().scan(
            moduleName: "Fixture",
            files: [.init(path: "Fixture.swift", content: "func read() -> Int { 1 }")],
        )
        let coverage = try SourceCoverage(
            planner: .init(module: module, dependencyModules: []),
            inventories: [.init(
                module: SourceScanner().scan(moduleName: "Native", files: []),
                reason: "Native boundary",
                excludedFiles: [.init(path: "Credentials.swift", reason: "Credential boundary")],
            )],
        )
        let data = try JSONEncoder().encode(coverage)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modules = try #require(object["modules"] as? [[String: Any]])
        #expect(modules.count == 2)
        for (encoded, expected) in zip(modules, coverage.modules) {
            #expect(encoded["module"] as? String == expected.module.rawValue)
            let declarations = try #require(encoded["declarations"] as? [[String: Any]])
            #expect(declarations.compactMap { $0["id"] as? String } == expected.declarations
                .map(\.id.rawValue))
        }
        let decoded = try JSONDecoder().decode(SourceCoverage.self, from: data)
        #expect(decoded.modules.map(\.module.rawValue) == ["Fixture", "Native"])
        #expect(decoded.modules.flatMap(\.declarations).map(\.id.rawValue) == coverage.modules
            .flatMap(\.declarations).map(\.id.rawValue))
    }

    @Test func allDeclarationsKeepConditionsAndFinalPlannerReasons() throws {
        let source = SourceFile(path: "Fixture.swift", content: """
        struct Value {}
        func unsupported(_ value: Value) -> Value { value }
        #if DEBUG
        func debugOnly() -> Int { 1 }
        #else
        func releaseOnly() -> Int { 2 }
        #endif
        """)
        let module = try SourceScanner().scan(moduleName: "Fixture", files: [source])
        let coverage = try SourceCoverage(
            planner: .init(module: module, dependencyModules: []),
            inventories: [],
        )
        let rows = try #require(coverage.modules.first).declarations
        #expect(rows.map(\.id.rawValue) == module.declarations.map(\.declarationID))
        let original = try #require(module.declarations.first { $0.name == "unsupported" })
        #expect(original.unsupportedReason == nil)
        let unsupported = try #require(rows.first { $0.name == "unsupported" })
        guard case let .unsupported(reason) = unsupported.plannedAvailability else {
            Issue.record("Coverage lost the planner's final rejection"); return
        }
        #expect(reason.contains("Sendable"))
        #expect(rows.first { $0.name == "Value" }?.plannedAvailability == .inspectable)
        for name in ["debugOnly", "releaseOnly"] {
            let row = try #require(rows.first { $0.name == name })
            #expect(!row.conditions.isEmpty)
            #expect(row.plannedAvailability == .callable)
            #expect(row.sourceSHA256 == source.sha256)
        }
    }

    @Test func emptyModulesAndExcludedSourceArePreservedWithoutCredentialContent() throws {
        let empty = try SourceScanner().scan(moduleName: "Empty", files: [])
        let native = try SourceScanner().scan(
            moduleName: "Native",
            files: [.init(path: "Native.swift", content: "func secretAction() {}")],
        )
        let coverage = try SourceCoverage(
            planner: .init(module: empty, dependencyModules: []),
            inventories: [.init(
                module: native,
                reason: "Native boundary",
                excludedFiles: [.init(path: "Keychain.swift", reason: "Credential boundary")],
            )],
        )
        #expect(coverage.modules.count == 2)
        #expect(coverage.modules.first?.declarations.isEmpty == true)
        let rows = try #require(coverage.modules.last).declarations
        #expect(rows.first?.origin == .sourceOnly)
        #expect(rows.first?.plannedAvailability == .unsupported("Native boundary"))
        let excluded = try #require(rows.last)
        #expect(excluded.origin == .excludedFile)
        #expect(excluded.source == nil && excluded.sourceSHA256 == nil)
        #expect(excluded.plannedAvailability == .unsupported("Credential boundary"))
        #expect(try !String(decoding: JSONEncoder().encode(coverage), as: UTF8.self)
            .contains("\"content\""))
    }
}
