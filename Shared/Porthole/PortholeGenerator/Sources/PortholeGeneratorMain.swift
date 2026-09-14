import Darwin
import Foundation

/// Build-tool executable: deterministic outputs and a failing diagnostic for malformed input.
@main
enum PortholeGeneratorMain {
    static func main() {
        do { try generate(arguments: Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError
                .write(Data("error: Porthole generation failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func generate(arguments: [String]) throws {
        let options = try GeneratorOptions(arguments: arguments)
        let files = try options.sourcePaths.map { path in
            try SourceFile(
                path: options.relativePath(path),
                content: String(contentsOfFile: path, encoding: .utf8),
            )
        }
        let environment = ProcessInfo.processInfo.environment
        let build = try BuildMetadataResolver.resolve(
            environment: environment,
            compilerVersion: BuildMetadataResolver.installedCompilerVersion,
        )
        let module = try SourceScanner().scan(
            moduleName: options.moduleName,
            files: files,
            build: build,
        )
        let dependencyFiles = try options.dependencySourcePaths.map { path in
            try SourceFile(
                path: options.relativePath(path),
                content: String(contentsOfFile: path, encoding: .utf8),
            )
        }
        // Dependency inventories provide isolation facts, not executable bindings or bundled
        // source.
        let dependencies = try dependencyFiles.isEmpty ? [] : [SourceScanner().scan(
            moduleName: "Dependencies",
            files: dependencyFiles,
            validateCollisions: false,
        )]
        let inventories: [SourceInventory]
        if let path = options.inventoryManifestPath {
            let manifest = try JSONDecoder().decode(
                SourceInventoryManifest.self,
                from: Data(contentsOf: URL(fileURLWithPath: path)),
            )
            inventories = try manifest.inventories(options: options, build: build)
        } else {
            inventories = []
        }
        let planner = BindingPlanner(module: module, dependencyModules: dependencies)
        let source = try BindingEmitter(planner: planner, inventories: inventories).emit()
        try writeIfChanged(Data(source.utf8), to: options.outputPath)
        if let catalogPath = options.catalogPath {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            try writeIfChanged(
                encoder.encode(SourceCoverage(planner: planner, inventories: inventories)),
                to: catalogPath,
            )
        }
    }

    private static func writeIfChanged(_ data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path),
           try Data(contentsOf: url) == data { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try data.write(to: url, options: .atomic)
    }
}

struct GeneratorOptions {
    let moduleName: String
    let rootPath: String
    let outputPath: String
    let catalogPath: String?
    let sourcePaths: [String]
    let dependencySourcePaths: [String]
    let inventoryManifestPath: String?

    init(arguments: [String]) throws {
        var options: [String: String] = [:]
        var sources: [String] = []
        var dependencies: [String] = []
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count
            else { throw GeneratorError.arguments("Missing value for \(option).") }
            let value = arguments[index + 1]
            switch option {
                case "--source": sources.append(value)
                case "--dependency-source": dependencies.append(value)
                case "--module", "--root", "--output", "--catalog",
                     "--inventory-manifest": options[option] = value
                default: throw GeneratorError.arguments("Unknown argument \(option).")
            }
            index += 2
        }
        guard let moduleName = options["--module"], let rootPath = options["--root"],
              let outputPath = options["--output"]
        else {
            throw GeneratorError
                .arguments(
                    "Usage: PortholeGenerator --module NAME --root PATH --output FILE [--catalog FILE] --source FILE [--source FILE ...]",
                )
        }
        self.moduleName = moduleName
        self.rootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        self.outputPath = outputPath
        catalogPath = options["--catalog"]
        sourcePaths = sources.sorted()
        dependencySourcePaths = dependencies.sorted()
        inventoryManifestPath = options["--inventory-manifest"]
    }

    func relativePath(_ path: String) throws -> String {
        let canonical = URL(fileURLWithPath: path).standardizedFileURL.path
        let prefix = rootPath + "/"
        guard canonical.hasPrefix(prefix) else {
            throw GeneratorError.arguments("Source paths must be inside the package root.")
        }
        return String(canonical.dropFirst(prefix.count))
    }
}
