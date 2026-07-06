import ForemanCore
import Foundation

/// Presentation helpers for a copy's provenance, shared by the sidebar row and
/// the worker detail so the mapping lives in one place and the views stay thin.
extension CopyProvenance {
    /// The parent repository's display name (its directory name).
    var parentName: String {
        URL(fileURLWithPath: parentRepoID.rawValue).lastPathComponent
    }

    /// Localized "Worktree"/"Clone".
    var kindText: LocalizedStringResource {
        switch kind {
            case .worktree: .provenanceWorktree
            case .clone: .provenanceClone
        }
    }

    /// SF Symbol that stands in for the copy kind.
    var badgeSymbol: String {
        switch kind {
            case .worktree: "arrow.triangle.branch"
            case .clone: "doc.on.doc"
        }
    }
}
