import Foundation
@testable import TestImpactIndex

/// Temporary host Swift program with a deterministic full-run oracle; no simulator or repository
/// sources change.
final class CompilerFixture {
    struct Output {
        let status: Int32
        let output: String
    }

    let root: URL
    private var files: [String] = []

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("impact fixture \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func write(_ name: String, _ source: String) throws {
        try source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        if !files.contains(name) { files.append(name) }
    }

    func build() throws {
        let output = try execute("/usr/bin/xcrun", [
            "swiftc",
            "-parse-as-library",
            "-module-name",
            "ImpactFixture",
            "-module-cache-path",
            root.appendingPathComponent("module-cache").path,
            "-index-store-path",
            root.appendingPathComponent("index").path,
            "-o",
            root.appendingPathComponent("oracle").path,
        ] + files.map { root.appendingPathComponent($0).path })
        guard output.status == 0 else { throw FixtureError.compiler(output.output) }
    }

    func run() throws -> Output {
        try execute(root.appendingPathComponent("oracle").path, [])
    }

    func collect() throws -> [IndexedFile] {
        let compiler = try execute("/usr/bin/xcrun", ["--find", "swiftc"])
        let library = URL(fileURLWithPath: compiler.output
            .trimmingCharacters(in: .whitespacesAndNewlines))
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib/libIndexStore.dylib")
        return try IndexCollector().collect(IndexRequest(
            root: root.path,
            files: files,
            indexStore: root.appendingPathComponent("index").path,
            database: root.appendingPathComponent("db-\(UUID().uuidString)").path,
            library: library.path,
        ))
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) }
        catch { FileHandle.standardError.write(Data("fixture cleanup failed: \(error)\n".utf8)) }
    }

    private func execute(_ executable: String, _ arguments: [String]) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Output(
            status: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self),
        )
    }

    private enum FixtureError: Error {
        case compiler(String)
    }
}
