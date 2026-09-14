import Foundation
@testable import PortholeGenerator
import Testing

struct PortholeGeneratorMainTests {
    @Test func requiresKnownArgumentsAndContainedSourcePaths() throws {
        let options = try GeneratorOptions(arguments: [
            "--module",
            "Fixture",
            "--root",
            "/tmp/Fixture",
            "--output",
            "/tmp/Generated.swift",
            "--catalog",
            "/tmp/catalog.json",
        ])
        #expect(options.catalogPath == "/tmp/catalog.json")
        #expect(try options
            .relativePath("/tmp/Fixture/Sources/Engine.swift") == "Sources/Engine.swift")
        #expect(throws: GeneratorError.self) { try options.relativePath("/tmp/Other/Secret.swift") }
        #expect(throws: GeneratorError.self) { try GeneratorOptions(arguments: [
            "--unknown",
            "value",
        ]) }
        #expect(throws: GeneratorError.self) { try GeneratorOptions(arguments: ["--module"]) }
    }

    @Test func catalogReportIsOptionalButItsArgumentStillRequiresAPath() throws {
        let arguments = [
            "--module",
            "Fixture",
            "--root",
            "/tmp/Fixture",
            "--output",
            "/tmp/Generated.swift",
        ]
        #expect(try GeneratorOptions(arguments: arguments).catalogPath == nil)
        #expect(throws: GeneratorError.self) {
            try GeneratorOptions(arguments: arguments + ["--catalog"])
        }
        #expect(throws: GeneratorError.self) {
            try GeneratorOptions(arguments: ["--module", "Fixture", "--root", "/tmp/Fixture"])
        }
    }

    @Test func omittingTheReportPreservesEmbeddedSourceAndCompleteCoverage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortholeGeneratorOutput-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Could not remove generator output fixture: \(error)") }
        }
        let original = directory.appendingPathComponent("Fixture.swift")
        let content = """
        private let dirtyBuildMarker: Int = 17
        #if DEBUG
        func debugOnly() -> Int { dirtyBuildMarker }
        #else
        func releaseOnly() -> Int { dirtyBuildMarker }
        #endif
        func unsupported(_ callback: () -> Void) { callback() }
        """
        try content.write(to: original, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("PluginOutput")
        let swift = output.appendingPathComponent("PortholeGeneratedModule.swift")
        let arguments = [
            "--module",
            "Fixture",
            "--root",
            directory.path,
            "--output",
            swift.path,
            "--source",
            original.path,
        ]
        try PortholeGeneratorMain.generate(arguments: arguments)
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: output.path) == [swift.lastPathComponent])
        let embedded = try String(contentsOf: swift, encoding: .utf8)
        let report = directory.appendingPathComponent("Reports/Fixture.porthole.json")
        try PortholeGeneratorMain.generate(arguments: arguments + ["--catalog", report.path])
        #expect(try String(contentsOf: swift, encoding: .utf8) == embedded)
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: output.path) == [swift.lastPathComponent])

        let archivePrefix = "    public static let sourceArchiveJSON = "
        let archiveLine = try #require(embedded.split(separator: "\n")
            .first { $0.hasPrefix(archivePrefix) })
        let archiveJSON = try JSONDecoder().decode(
            String.self,
            from: Data(archiveLine.dropFirst(archivePrefix.count).utf8),
        )
        let archive = try JSONDecoder().decode([SourceFile].self, from: Data(archiveJSON.utf8))
        #expect(archive.count == 1)
        #expect(archive.first?.content == content)
        #expect(archive.first?.sha256 == SourceFile(path: "Fixture.swift", content: content).sha256)

        let coveragePrefix = "    public static let coverageJSON = "
        let coverageLine = try #require(embedded.split(separator: "\n")
            .first { $0.hasPrefix(coveragePrefix) })
        let coverageJSON = try JSONDecoder().decode(
            String.self,
            from: Data(coverageLine.dropFirst(coveragePrefix.count).utf8),
        )
        let embeddedCoverage = try JSONDecoder().decode(
            SourceCoverage.self,
            from: Data(coverageJSON.utf8),
        )
        let reportedCoverage = try JSONDecoder().decode(
            SourceCoverage.self,
            from: Data(contentsOf: report),
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(embeddedCoverage) == encoder.encode(reportedCoverage))
        let declarations = try #require(embeddedCoverage.modules.first).declarations
        #expect(declarations.contains { $0.name == "debugOnly" && !$0.conditions.isEmpty })
        #expect(declarations.contains { $0.name == "releaseOnly" && !$0.conditions.isEmpty })
        let unsupported = try #require(declarations.first { $0.name == "unsupported" })
        guard case .unsupported = unsupported.plannedAvailability else {
            Issue.record("The embedded catalog lost its unsupported signature"); return
        }
    }
}
