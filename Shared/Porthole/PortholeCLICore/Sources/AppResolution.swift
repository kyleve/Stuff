import Foundation
import PortholeClientKit

/// Resolves the `--app` selector against the set of paired apps.
public enum AppResolution {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case nonePaired
        case ambiguous([String])
        case notFound(String)

        public var description: String {
            switch self {
                case .nonePaired:
                    "No paired apps. Run `porthole pair` first."
                case let .ambiguous(matches):
                    "Ambiguous --app; matches: \(matches.joined(separator: ", ")). Be more specific."
                case let .notFound(selector):
                    "No paired app matches `\(selector)`."
            }
        }
    }

    /// Picks a paired app. With no `selector`, requires exactly one paired app.
    /// With a `selector`, matches by bundle id (exact) or app name / device name
    /// (case-insensitive substring); the match must be unique.
    public static func resolve(selector: String?, from apps: [PairedApp]) throws -> PairedApp {
        guard let selector else {
            switch apps.count {
                case 0: throw Failure.nonePaired
                case 1: return apps[0]
                default: throw Failure.ambiguous(apps.map(\.appName))
            }
        }

        let lowered = selector.lowercased()
        let matches = apps.filter { app in
            app.bundleID == selector
                || app.appName.lowercased().contains(lowered)
                || app.deviceName.lowercased().contains(lowered)
        }
        switch matches.count {
            case 0: throw Failure.notFound(selector)
            case 1: return matches[0]
            default: throw Failure.ambiguous(matches.map(\.appName))
        }
    }
}
