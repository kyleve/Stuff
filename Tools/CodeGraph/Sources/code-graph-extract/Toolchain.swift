import Foundation

/// Locates toolchain artifacts the extractor depends on.
enum Toolchain {
    /// Absolute path to the active toolchain's `libIndexStore.dylib`. The
    /// library must match the toolchain that produced the index store, so by
    /// default we derive it from the same `swift` that `xcrun` resolves.
    static func libIndexStorePath(override: String?) throws -> String {
        if let override {
            guard FileManager.default.fileExists(atPath: override) else {
                throw ExtractError.libIndexStoreNotFound(override)
            }
            return override
        }
        // `xcrun --find swift` -> .../XcodeDefault.xctoolchain/usr/bin/swift, and
        // libIndexStore lives next door at .../usr/lib/libIndexStore.dylib.
        let swiftPath = try Shell.capture("/usr/bin/xcrun", ["--find", "swift"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usr = URL(fileURLWithPath: swiftPath)
            .deletingLastPathComponent() // usr/bin
            .deletingLastPathComponent() // usr
        let lib = usr.appendingPathComponent("lib/libIndexStore.dylib")
        guard FileManager.default.fileExists(atPath: lib.path) else {
            throw ExtractError.libIndexStoreNotFound(lib.path)
        }
        return lib.path
    }

    /// The `HEAD` commit of the repo, if it is a git working copy.
    static func gitCommit(repoPath: String) -> String? {
        let output = try? Shell.capture("/usr/bin/git", ["-C", repoPath, "rev-parse", "HEAD"])
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
