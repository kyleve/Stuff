import Foundation
import WhereCore

public actor FileTrackingStateStore: TrackingStateStore {
    private let store: JSONFileStore<TrackingState>

    public init(fileURL: URL) {
        store = JSONFileStore(fileURL: fileURL)
    }

    public func load() async -> TrackingState {
        store.load(
            defaultValue: TrackingState(
                authorizationStatus: .notDetermined,
            ),
        )
    }

    public func save(_ state: TrackingState) async {
        store.save(state)
    }
}
