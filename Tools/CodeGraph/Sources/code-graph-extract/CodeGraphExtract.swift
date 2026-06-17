import ArgumentParser
import CodeGraphModel
import Foundation

@main
struct CodeGraphExtract: ParsableCommand {
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

    @Flag(help: "Keep running and re-extract whenever the index store changes.")
    var watch = false

    @Option(help: "Debounce, in seconds, before re-extracting after a change in --watch mode.")
    var watchDebounce: Double = 1.0

    func run() throws {
        let repoPath = URL(fileURLWithPath: repo).standardizedFileURL.path
        let libPath = try Toolchain.libIndexStorePath(override: toolchainLib)
        let storePath = try resolveStorePath(repoPath: repoPath)
        let outputPath = output ?? (repoPath + "/Tools/CodeGraph/.codegraph/graph.json")

        log("opening index store at \(storePath)")
        let reader = try IndexStoreReader(storePath: storePath, libIndexStorePath: libPath)
        try extractAndWrite(reader: reader, repoPath: repoPath, outputPath: outputPath)

        guard watch else { return }
        try startWatching(
            reader: reader,
            storePath: storePath,
            repoPath: repoPath,
            outputPath: outputPath,
        )
    }

    private func startWatching(
        reader: IndexStoreReader,
        storePath: String,
        repoPath: String,
        outputPath: String,
    ) throws {
        let unitsDirectory = unitsDirectory(storePath: storePath)
        let watcher = DataStoreWatcher(directory: unitsDirectory, debounce: watchDebounce) {
            do {
                reader.refresh()
                try extractAndWrite(reader: reader, repoPath: repoPath, outputPath: outputPath)
            } catch {
                FileHandle.standardError.write(Data("==> watch re-extract failed: \(error)\n".utf8))
            }
        }
        try watcher.start()
        log("watching \(unitsDirectory) for changes (ctrl-C to stop)")
        watcher.wait()
    }

    private func unitsDirectory(storePath: String) -> String {
        for candidate in ["\(storePath)/v5/units", "\(storePath)/units"]
            where FileManager.default.fileExists(atPath: candidate)
        {
            return candidate
        }
        return storePath
    }

    /// Harvest the graph from the (already opened) store and write graph.json.
    func extractAndWrite(reader: IndexStoreReader, repoPath: String, outputPath: String) throws {
        log("harvesting graph")
        let content = GraphBuilder(db: reader.db, repoPath: repoPath).build()
        let graph = CodeGraph(
            generatedAt: Date(),
            repoPath: repoPath,
            commit: Toolchain.gitCommit(repoPath: repoPath),
            modules: content.modules,
            nodes: content.nodes,
            edges: content.edges,
        )
        try write(graph, to: outputPath)
        log("wrote \(content.nodes.count) nodes, \(content.edges.count) edges, "
            + "\(content.modules.count) modules -> \(outputPath)")
    }

    private func write(_ graph: CodeGraph, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try graph.encoded().write(to: url, options: .atomic)
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
