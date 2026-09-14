import Foundation

/// Source-only modules are visible as evidence but never receive generated executable bindings.
struct SourceInventory: Codable {
    struct ExcludedFile: Codable {
        let path: String
        let reason: String
    }

    let module: SourceModule
    let reason: String
    let excludedFiles: [ExcludedFile]
}

/// The application exporter supplies the exact dependency closure and explicit source exclusions.
struct SourceInventoryManifest: Decodable {
    struct Module: Decodable {
        let name: String
        let reason: String
        let sources: [String]
        let excludedFiles: [SourceInventory.ExcludedFile]
    }

    let modules: [Module]

    func inventories(
        options: GeneratorOptions,
        build: SourceModule.BuildMetadata,
    ) throws -> [SourceInventory] {
        guard Set(modules.map(\.name)).count == modules.count,
              !modules.contains(where: { $0.name == options.moduleName })
        else {
            throw GeneratorError
                .arguments(
                    "Source-only module names must be unique and separate from the binding module.",
                )
        }
        return try modules.sorted { $0.name < $1.name }.map { entry in
            guard !entry.name.isEmpty, !entry.reason.isEmpty else {
                throw GeneratorError
                    .arguments("Source-only modules require a name and exclusion reason.")
            }
            let excluded = try entry.excludedFiles.map { file in
                guard !file.reason.isEmpty else {
                    throw GeneratorError.arguments("Excluded source files require a reason.")
                }
                return try SourceInventory.ExcludedFile(
                    path: options.relativePath(file.path),
                    reason: file.reason,
                )
            }.sorted { $0.path < $1.path }
            let excludedPaths = Set(excluded.map(\.path))
            let paths = try entry.sources.map { try options.relativePath($0) }
            guard Set(paths).count == paths.count,
                  excludedPaths.count == excluded.count,
                  excludedPaths.isDisjoint(with: paths)
            else {
                throw GeneratorError
                    .arguments("Source inventory paths must be unique and cannot also be excluded.")
            }
            let files = try entry.sources.sorted().map { path in
                try SourceFile(
                    path: options.relativePath(path),
                    content: String(contentsOfFile: path, encoding: .utf8),
                )
            }
            let module = try SourceScanner().scan(
                moduleName: entry.name,
                files: files,
                validateCollisions: false,
                build: build,
            )
            return SourceInventory(module: module, reason: entry.reason, excludedFiles: excluded)
        }
    }
}
