import Foundation
import PeriscopeCore

/// Which build of the app is running: the marketing version, the build number,
/// the commit it was built from, and how the Swift compiler was invoked — read
/// back from the bundle's Info.plist.
///
/// The version keys are Xcode's; the rest are stamped into the built product by
/// the `Where` target's "Stamp Build Info" script phase (see the root
/// `AGENTS.md`). Only the app target is stamped, so a bundle that never ran that
/// phase — the RegionViewer developer tool, `StuffTestHost`, an app extension —
/// reports `commit == nil` and `compilation == nil` rather than placeholders,
/// and the About screen says the build is unidentified instead of showing an
/// invented one.
public struct BuildInfo: Sendable, Equatable {
    /// The commit the binary was built from, when the bundle carries one.
    public struct Commit: Sendable, Equatable {
        /// Abbreviated (12-character) commit hash.
        public let sha: String
        /// Whether the working tree had uncommitted changes at build time, so a
        /// SHA from a developer build can't be mistaken for a reproducible one.
        public let isDirty: Bool

        public init(sha: String, isDirty: Bool) {
            self.sha = sha
            self.isDirty = isDirty
        }
    }

    /// How the Swift compiler was invoked, when the bundle carries it.
    ///
    /// ``optimizationLevel`` is the load-bearing field: a measured duration
    /// from an `-Onone` build says nothing about the shipping app, and the
    /// configuration can't answer that on its own, since a `Debug`
    /// configuration can be compiled with `-O`.
    public struct Compilation: Sendable, Equatable {
        /// `CONFIGURATION` — `Debug` or `Release` for the standard schemes.
        public let configuration: String
        /// `SWIFT_OPTIMIZATION_LEVEL` — `-Onone`, `-O`, or `-Osize`.
        public let optimizationLevel: String
        /// `SWIFT_COMPILATION_MODE` — `wholemodule`, or a per-file mode
        /// (`singlefile` for a stock Debug build) — or `nil` when the build
        /// didn't export one. Optional on its own rather than gating the whole
        /// value, because it's the least load-bearing of the three: dropping the
        /// optimization level over a missing compilation mode would defeat the
        /// point of reading either.
        public let mode: String?

        public init(configuration: String, optimizationLevel: String, mode: String?) {
            self.configuration = configuration
            self.optimizationLevel = optimizationLevel
            self.mode = mode
        }
    }

    /// `CFBundleShortVersionString`, or `nil` in a bundle without one.
    public let version: String?
    /// `CFBundleVersion`, or `nil` in a bundle without one.
    public let build: String?
    /// The stamped commit, or `nil` in an unstamped bundle.
    public let commit: Commit?
    /// The stamped compiler settings, or `nil` in an unstamped bundle.
    public let compilation: Compilation?

    /// Reads the build metadata out of `bundle`. Pass `.main` from the app; the
    /// bundle is explicit (no default) so a caller can't accidentally read the
    /// wrong one from an extension or a test host.
    public static func current(bundle: Bundle) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        return BuildInfo(infoDictionary: info.compactMapValues { $0 as? String })
    }

    /// Builds from a raw Info.plist string dictionary. `@_spi(Testing)` because
    /// production always goes through ``current(bundle:)`` — synthesizing a
    /// bundle just to test the stamped / unstamped / dirty readings isn't worth
    /// it.
    @_spi(Testing)
    public init(infoDictionary: [String: String]) {
        version = Self.value(for: .version, in: infoDictionary)
        build = Self.value(for: .build, in: infoDictionary)
        commit = Self.commit(from: infoDictionary)
        compilation = Self.compilation(from: infoDictionary)
    }

    private static func commit(from info: [String: String]) -> Commit? {
        guard
            let sha = value(for: .gitSHA, in: info),
            let raw = value(for: .gitStatus, in: info),
            let status = Status(rawValue: raw)
        else {
            return nil
        }
        switch status {
            case .clean: return Commit(sha: sha, isDirty: false)
            case .dirty: return Commit(sha: sha, isDirty: true)
            // The stamp ran but git couldn't answer, so the SHA beside it is the
            // literal "unknown" placeholder rather than a hash.
            case .unknown: return nil
        }
    }

    private static func compilation(from info: [String: String]) -> Compilation? {
        guard
            let configuration = determinedValue(for: .configuration, in: info),
            let optimizationLevel = determinedValue(for: .optimizationLevel, in: info)
        else {
            return nil
        }
        return Compilation(
            configuration: configuration,
            optimizationLevel: optimizationLevel,
            mode: determinedValue(for: .compilationMode, in: info),
        )
    }

    /// The value for `key`, treating a missing entry and a blank one alike — a
    /// plist string key can exist and hold `""`.
    private static func value(for key: Key, in info: [String: String]) -> String? {
        guard
            let value = info[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    /// ``value(for:in:)``, also rejecting the ``unavailable`` placeholder — a
    /// stamped key that reads `unknown` carries no more information than a
    /// missing one, and reporting the literal string as a configuration or an
    /// optimization level would read as a real answer.
    private static func determinedValue(for key: Key, in info: [String: String]) -> String? {
        guard let value = value(for: key, in: info), value != unavailable else {
            return nil
        }
        return value
    }

    /// What the stamp script writes for a value it couldn't determine: a
    /// checkout without git metadata, or a build setting Xcode didn't export.
    private static let unavailable = "unknown"

    /// The Info.plist keys read here — the two Xcode writes and the five the
    /// stamp script adds. The script writes the same literals; they have to
    /// match.
    private enum Key: String {
        case version = "CFBundleShortVersionString"
        case build = "CFBundleVersion"
        case gitSHA = "WhereGitSHA"
        case gitStatus = "WhereGitStatus"
        case configuration = "WhereConfiguration"
        case optimizationLevel = "WhereSwiftOptimizationLevel"
        case compilationMode = "WhereSwiftCompilationMode"
    }

    /// The values the stamp script writes for `WhereGitStatus`.
    private enum Status: String {
        case clean
        case dirty
        case unknown
    }
}

extension BuildInfo {
    /// The build attributes to stamp on a Periscope logging session.
    ///
    /// Only what this bundle can actually name: an unstamped bundle yields an
    /// empty dictionary, and a session then claims nothing rather than claiming
    /// it was built from a commit called `unknown`. The mapping lives beside the
    /// plist reading so a newly stamped key can't be added to one and forgotten
    /// in the other.
    public var logSessionAttributes: [LogSessionAttributeKey: String] {
        var attributes: [LogSessionAttributeKey: String] = [:]
        if let commit {
            attributes[.commit] = commit.sha
            let status: LogSessionAttributeKey.CommitStatus = commit.isDirty ? .dirty : .clean
            attributes[.commitStatus] = status.rawValue
        }
        if let compilation {
            attributes[.configuration] = compilation.configuration
            attributes[.optimizationLevel] = compilation.optimizationLevel
            // Assigning `nil` inserts nothing, which is what an unexported
            // compilation mode should leave behind.
            attributes[.compilationMode] = compilation.mode
        }
        return attributes
    }
}
