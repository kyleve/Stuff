import CodeGraphModel
import CoreGraphics
import Foundation

/// A serializable snapshot of everything the viewer remembers about how a graph
/// is arranged and filtered: pinned positions (keyed by USR), the active
/// filters, and expand/focus state.
struct ViewerState: Codable {
    var pins: [String: CGPoint] = [:]
    var expanded: Set<String> = []
    var focusRoot: String?
    var focusDepth = 1
    var showExternal = false
    var showTests = true
    var showModules = false
    var includedEdgeKinds: Set<EdgeKind> = GraphViewModel.defaultEdgeKinds
    var includedNodeKinds: Set<NodeKind> = GraphViewModel.filterableKinds
    var hiddenModules: Set<String> = []
    var nameQuery = ""
}

/// A user-named arrangement they can return to.
struct SavedView: Codable, Identifiable {
    var id = UUID()
    var name: String
    var state: ViewerState
}

/// What gets persisted per repository: the working state plus saved views.
struct ViewerRecord: Codable {
    var current = ViewerState()
    var savedViews: [SavedView] = []
}

/// Stores a ``ViewerRecord`` per repository in the app container (UserDefaults).
/// Keyed by repo path so pointing the viewer at different repos keeps their
/// arrangements separate.
struct ViewerPersistence {
    private let defaults: UserDefaults

    /// Defaults to the app container; tests inject an isolated suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(repoPath: String) -> ViewerRecord {
        guard
            let data = defaults.data(forKey: key(repoPath)),
            let record = try? JSONDecoder().decode(ViewerRecord.self, from: data)
        else {
            return ViewerRecord()
        }
        return record
    }

    func save(_ record: ViewerRecord, repoPath: String) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: key(repoPath))
    }

    private func key(_ repoPath: String) -> String {
        "viewerRecord:\(repoPath)"
    }
}
