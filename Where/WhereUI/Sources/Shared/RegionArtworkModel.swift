import Foundation
import Observation

/// Publishes complete artwork only for the latest load. A matching display key
/// can retain existing artwork while a more specific task identity refreshes it.
@MainActor
@Observable
final class RegionArtworkModel<Key: Equatable, Artwork> {
    private enum State {
        case idle
        case loading(key: Key, token: UUID, previous: Artwork?)
        case loaded(key: Key, artwork: Artwork)
    }

    private var state = State.idle

    func artwork(for key: Key) -> Artwork? {
        switch state {
            case .idle:
                nil
            case let .loading(current, _, previous):
                current == key ? previous : nil
            case let .loaded(current, artwork):
                current == key ? artwork : nil
        }
    }

    func load(for key: Key, operation: @MainActor () async -> Artwork?) async {
        guard !Task.isCancelled else { return }
        let token = UUID()
        state = .loading(key: key, token: token, previous: artwork(for: key))
        let loaded = await operation()
        guard !Task.isCancelled,
              case let .loading(_, currentToken, _) = state,
              currentToken == token
        else { return }
        if let loaded {
            state = .loaded(key: key, artwork: loaded)
        } else {
            state = .idle
        }
    }
}
