import Foundation
import PackagePlugin

/// Instruments the target's complete source inventory without changing its compilation mode.
@main
struct PortholeBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
        guard let target = target as? SwiftSourceModuleTarget else { return [] }
        let sources = target.sourceFiles(withSuffix: "swift").map(\.url)
            .sorted { $0.path < $1.path }
        let output = context.pluginWorkDirectoryURL
            .appendingPathComponent("PortholeGeneratedModule.swift")
        let dependencies = sourceDependencies(of: target)
        var arguments = [
            "--module",
            target.moduleName,
            "--root",
            context.package.directoryURL.path,
            "--output",
            output.path,
        ]
        for source in sources {
            arguments += ["--source", source.path]
        }
        for dependency in dependencies {
            arguments += ["--dependency-source", dependency.path]
        }
        return try [.buildCommand(
            displayName: "Generate Porthole bindings for \(target.moduleName)",
            executable: context.tool(named: "PortholeGenerator").url,
            arguments: arguments,
            inputFiles: sources + dependencies,
            outputFiles: [output],
        )]
    }

    private func sourceDependencies(of target: SwiftSourceModuleTarget) -> [URL] {
        var visited: Set<String> = [target.id]
        var result: [URL] = []
        func visit(_ dependency: any Target) {
            guard visited.insert(dependency.id).inserted else { return }
            guard let source = dependency as? SwiftSourceModuleTarget else { return }
            if !source.moduleName.hasPrefix("Porthole") {
                result += source.sourceFiles(withSuffix: "swift").map(\.url)
            }
            for child in source.dependencies {
                switch child {
                    case let .target(target): visit(target)
                    case .product: break
                    @unknown default: break
                }
            }
        }
        for dependency in target.dependencies {
            switch dependency {
                case let .target(target): visit(target)
                case .product: break
                @unknown default: break
            }
        }
        return result.sorted { $0.path < $1.path }
    }
}
