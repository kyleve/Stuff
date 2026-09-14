import Foundation
@testable import PortholeGenerator
import Testing

struct SourceInventoryTests {
    @Test func rejectsOverlappingExclusionsBeforeReadingSource() throws {
        let options = try options()
        let manifest = SourceInventoryManifest(modules: [.init(
            name: "ControlPlane",
            reason: "Native approval boundary",
            sources: ["/tmp/Inventory/Secrets.swift"],
            excludedFiles: [.init(
                path: "/tmp/Inventory/Secrets.swift",
                reason: "Credential machinery",
            )],
        )])
        #expect(throws: GeneratorError.self) { try manifest.inventories(
            options: options,
            build: build,
        ) }
    }

    @Test func excludedFilePathsStayInsideTheSourceRoot() throws {
        let options = try options()
        let manifest = SourceInventoryManifest(modules: [.init(
            name: "ControlPlane",
            reason: "Native approval boundary",
            sources: [],
            excludedFiles: [.init(
                path: "/tmp/Other/Secrets.swift",
                reason: "Credential machinery",
            )],
        )])
        #expect(throws: GeneratorError.self) { try manifest.inventories(
            options: options,
            build: build,
        ) }
    }

    @Test func sourceOnlyModulesNeverReceiveExecutableBindings() throws {
        let module = try SourceScanner().scan(moduleName: "App", files: [])
        let controlPlane = try SourceScanner().scan(moduleName: "ControlPlane", files: [.init(
            path: "ControlPlane/Approval.swift",
            content: """
            import NonexistentFramework
            #if SOME_OTHER_CONFIGURATION
            @MainActor func approve() -> Bool { true }
            #endif
            """,
        )])
        let source = try BindingEmitter(
            planner: .init(module: module, dependencyModules: []),
            inventories: [
                .init(module: controlPlane, reason: "Native approval boundary", excludedFiles: [
                    .init(path: "ControlPlane/Secrets.swift", reason: "Credential machinery"),
                ]),
            ],
        ).emit()
        #expect(source.contains("module: .init(rawValue: \"ControlPlane\")"))
        #expect(source.contains("availability: .unsupported(\"Native approval boundary\")"))
        #expect(source.contains("ControlPlane:excluded-source:ControlPlane/Secrets.swift"))
        #expect(source.contains("registry.describe(capability0"))
        #expect(!source.contains("registry.register("))
        #expect(!source.contains("private static func invoke"))
        #expect(!source.contains("\nimport NonexistentFramework\n"))
        #expect(!source.contains("\n#if SOME_OTHER_CONFIGURATION\n"))
        #expect(source.contains("coverageJSON"))
        #expect(!source.contains("inventoryCatalogJSON"))
        let archiveLine = try #require(source.split(separator: "\n")
            .first { $0.contains("static let sourceArchiveJSON") })
        #expect(archiveLine.contains("Approval.swift"))
        #expect(!archiveLine.contains("Secrets.swift"))
    }

    private func options() throws -> GeneratorOptions {
        try GeneratorOptions(arguments: [
            "--module",
            "App",
            "--root",
            "/tmp/Inventory",
            "--output",
            "/tmp/Inventory/out.swift",
            "--catalog",
            "/tmp/Inventory/catalog.json",
        ])
    }

    private var build: SourceModule.BuildMetadata {
        .init(
            configuration: "Beta",
            toolchain: "Apple Swift fixture",
        )
    }

    @Test func sourceOnlyModulesInheritTheAppBuildLabels() throws {
        let manifest = SourceInventoryManifest(modules: [.init(
            name: "ControlPlane",
            reason: "Native approval boundary",
            sources: [],
            excludedFiles: [],
        )])
        let inventory = try #require(manifest.inventories(options: options(), build: build).first)
        #expect(inventory.module.build.configuration == "Beta")
        #expect(inventory.module.build.toolchain == "Apple Swift fixture")
    }
}
