import Foundation

/// Which build of the app is running: the marketing version, the build number,
/// and the commit it was built from — read back from the bundle's Info.plist.
///
/// The version keys are Xcode's; the commit keys are stamped into the built
/// product by the `Where` target's "Stamp Build Info" script phase (see the root
/// `AGENTS.md`). Only the app target is stamped, so a bundle that never ran that
/// phase — the RegionViewer developer tool, `StuffTestHost`, an app extension —
/// reports `commit == nil` rather than a placeholder, and the About screen says
/// the build is unidentified instead of showing an invented one.
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

    /// `CFBundleShortVersionString`, or `nil` in a bundle without one.
    public let version: String?
    /// `CFBundleVersion`, or `nil` in a bundle without one.
    public let build: String?
    /// The stamped commit, or `nil` in an unstamped bundle.
    public let commit: Commit?

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

    /// The Info.plist keys read here — the two Xcode writes and the two the
    /// stamp script adds. The script writes the same literals; they have to
    /// match.
    private enum Key: String {
        case version = "CFBundleShortVersionString"
        case build = "CFBundleVersion"
        case gitSHA = "WhereGitSHA"
        case gitStatus = "WhereGitStatus"
    }

    /// The values the stamp script writes for `WhereGitStatus`.
    private enum Status: String {
        case clean
        case dirty
        case unknown
    }
}
