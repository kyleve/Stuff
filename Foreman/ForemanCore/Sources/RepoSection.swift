import Foundation

/// A grouping of ``Repo``s for the sidebar: enabled repos on top, disabled
/// below, with favorites floated to the top of each group.
///
/// This is the pure ordering rule behind the "smarter" repo list. It lives in
/// Core (not the view) so the sectioning and sort are unit-tested; the app
/// target only renders a `Section` per element.
///
/// The struct itself is not actor-isolated (so its `Identifiable` conformance
/// stays nonisolated); only ``sections(from:)`` is `@MainActor`, since reading
/// each ``Repo``'s enabled/favorite state is main-actor work.
public struct RepoSection: Identifiable {
    /// Which repos a section holds. The `Kind` carries no display text —
    /// section titles are the view's concern.
    public enum Kind: Hashable, Sendable {
        /// Repos whose worker is enabled (the persisted desired state).
        case enabled
        /// Repos whose worker is disabled.
        case disabled
    }

    public let kind: Kind
    /// The section's repos, favorites first (see ``sections(from:)``).
    public let repos: [Repo]

    public var id: Kind {
        kind
    }

    public init(kind: Kind, repos: [Repo]) {
        self.kind = kind
        self.repos = repos
    }

    /// Splits `repos` into the enabled and disabled sections, floating
    /// favorites to the top of each. `repos` is expected already name-sorted
    /// (``RepoDiscovery`` sorts its listing), and the partition is stable, so
    /// non-favorites keep their alphabetical order and favorites lead each
    /// section in that same order. Empty sections are omitted, so an all-enabled
    /// list renders a single section.
    @MainActor
    public static func sections(from repos: [Repo]) -> [RepoSection] {
        func favoritesFirst(_ repos: [Repo]) -> [Repo] {
            repos.filter(\.isFavorite) + repos.filter { !$0.isFavorite }
        }

        return [
            RepoSection(kind: .enabled, repos: favoritesFirst(repos.filter(\.isEnabled))),
            RepoSection(kind: .disabled, repos: favoritesFirst(repos.filter { !$0.isEnabled })),
        ]
        .filter { !$0.repos.isEmpty }
    }
}
