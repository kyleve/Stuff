import ArgumentParser
import CodeGraphModel
import Foundation

@main
struct CodeGraphExtract: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "code-graph-extract",
        abstract: "Extract a type/relationship graph from a Swift repo's compiler index store.",
    )

    @Option(help: "Repository root. Defaults to the current directory.")
    var repo: String = FileManager.default.currentDirectoryPath

    @Option(
        help: "Where to write graph.json. Defaults to <repo>/Tools/CodeGraph/.codegraph/graph.json.",
    )
    var output: String?

    @Option(help: "Read an existing index store at this path instead of building.")
    var indexStorePath: String?

    @Option(help: "Override the path to libIndexStore.dylib (default: active toolchain).")
    var toolchainLib: String?

    @Option(help: "Xcode scheme to build for the dedicated index build.")
    var scheme: String = "Stuff-Workspace"

    @Option(help: "xcodebuild destination for the dedicated index build.")
    var destination: String = "platform=iOS Simulator,name=iPhone 17"

    @Option(help: "Derived-data path for the dedicated index build (holds the index store).")
    var derivedData: String?

    @Flag(help: "Use an index store from a prior build; never invoke xcodebuild.")
    var skipBuild = false

    func run() async throws {
        let repoPath = URL(fileURLWithPath: repo).standardizedFileURL.path
        let libPath = try Toolchain.libIndexStorePath(override: toolchainLib)

        let storePath = try resolveStorePath(repoPath: repoPath)
        log("opening index store at \(storePath)")
        let reader = try IndexStoreReader(storePath: storePath, libIndexStorePath: libPath)
        log("index opened: \(reader.symbolNameCount()) symbol names")
        // Harvesting the graph and writing graph.json lands in the next step.
    }

    private func resolveStorePath(repoPath: String) throws -> String {
        if let indexStorePath {
            return URL(fileURLWithPath: indexStorePath).standardizedFileURL.path
        }
        let derivedDataPath = derivedData
            ?? (repoPath + "/Tools/CodeGraph/.codegraph/DerivedData")
        let input = IndexStoreInput(
            repoPath: repoPath,
            derivedDataPath: derivedDataPath,
            scheme: scheme,
            destination: destination,
        )
        try input.ensureBuilt(skipBuild: skipBuild)
        return input.indexStorePath
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("==> \(message)\n".utf8))
    }
}
