#if DEBUG
    import Observation

    /// Builds one separate demo world and retains its scene through every synthetic pose.
    @MainActor @Observable
    final class DuoLayoutLabModel {
        enum State {
            case idle
            case loading
            case loaded(WhereFlyoverWorld)
            case failed(Error)
        }

        private(set) var state = State.idle
        private(set) var request = 0

        func load() async {
            guard case .idle = state else { return }
            state = .loading
            do {
                let world = try await WhereFlyoverWorld.build()
                try Task.checkCancellation()
                state = .loaded(world)
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error)
            }
        }

        func retry() {
            guard case .failed = state else { return }
            state = .idle
            request += 1
        }
    }
#endif
