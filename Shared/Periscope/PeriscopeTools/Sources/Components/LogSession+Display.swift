import Foundation
import PeriscopeCore

extension LogSession {
    /// One line naming the session in the viewer's session picker: when it
    /// started, and — as far as the session can say — which build produced it.
    ///
    /// The version and build number alone don't identify a build when an app
    /// pins both in its manifest, so every developer build reads the same pair.
    /// The commit and the optimization level are what let a reader tie old
    /// events to the code that produced them, and tell whether a recorded
    /// duration came off an optimized build. Both come from
    /// ``LogSession/attributes``, which a host app fills at bootstrap, so a
    /// session that named nothing renders as just the date and version.
    var displayLabel: String {
        var parts = [
            startedAt.formatted(date: .abbreviated, time: .shortened),
            "v\(appVersion) (\(buildNumber))",
        ]
        if let commit = attributes[.commit] {
            parts.append(dirtyMarker.map { "\(commit) \($0)" } ?? commit)
        }
        if let optimizationLevel = attributes[.optimizationLevel] {
            parts.append(optimizationLevel)
        }
        return parts.joined(separator: " · ")
    }

    /// `(dirty)` when the build came from a modified working tree, so two
    /// sessions from one SHA aren't read as the same code. `nil` when the tree
    /// was clean, when the session never said, and when it said something this
    /// build doesn't recognize — none of those may render as a clean tree, and
    /// none of them is worth a word in a picker row.
    private var dirtyMarker: String? {
        let status = attributes[.commitStatus]
            .flatMap(LogSessionAttributeKey.CommitStatus.init(rawValue:))
        return status == .dirty ? "(dirty)" : nil
    }
}
