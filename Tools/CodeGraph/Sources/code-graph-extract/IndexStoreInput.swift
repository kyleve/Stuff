import Foundation

/// Resolves the index store the extractor reads from: either a caller-supplied
/// path, or one produced by a dedicated, reproducible build into a fixed
/// derived-data directory.
struct IndexStoreInput {
    var repoPath: String
    var derivedDataPath: String
    var scheme: String
    var destination: String

    /// Xcode writes the compiler index store under the derived-data directory.
    var indexStorePath: String {
        derivedDataPath + "/Index.noindex/DataStore"
    }

    /// Ensure an index store exists at `indexStorePath`, building if needed.
    ///
    /// - Parameter skipBuild: when true, never invoke the build; require an
    ///   index store from a prior build to already be present.
    func ensureBuilt(skipBuild: Bool) throws {
        if skipBuild {
            try requireStore()
            return
        }
        try generateProject()
        try build()
        try requireStore()
    }

    private func requireStore() throws {
        guard FileManager.default.fileExists(atPath: indexStorePath) else {
            throw ExtractError.indexStoreNotFound(indexStorePath)
        }
    }

    private func generateProject() throws {
        log("tuist generate --no-open")
        try Shell.runStreaming(
            "/usr/bin/env",
            ["mise", "exec", "--", "tuist", "generate", "--no-open"],
            cwd: repoPath,
        )
    }

    private func build() throws {
        let workspace = repoPath + "/Stuff.xcworkspace"
        guard FileManager.default.fileExists(atPath: workspace) else {
            throw ExtractError.missingWorkspace(workspace)
        }
        log("xcodebuild build-for-testing (scheme: \(scheme))")
        // `build-for-testing` compiles the libraries, the app, and the test
        // bundles, so the "everything" scope (including tests) gets indexed.
        try Shell.runStreaming("/usr/bin/xcrun", [
            "xcodebuild",
            "build-for-testing",
            "-workspace",
            workspace,
            "-scheme",
            scheme,
            "-destination",
            destination,
            "-derivedDataPath",
            derivedDataPath,
            "COMPILER_INDEX_STORE_ENABLE=YES",
        ], cwd: repoPath)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("==> \(message)\n".utf8))
    }
}
