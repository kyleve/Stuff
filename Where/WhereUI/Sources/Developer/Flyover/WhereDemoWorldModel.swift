#if DEBUG
    import Observation

    /// Loads a demo world and retains its scene across synthetic layout changes.
    @MainActor @Observable
    final class WhereDemoWorldModel {
        enum State {
            case idle
            case loading
            case loaded(WhereFlyoverWorld)
            case failed(Error)
        }

        private(set) var state = State.idle
        private(set) var request = 0
        @ObservationIgnored private let buildWorld: @MainActor () async throws -> WhereFlyoverWorld

        init(buildWorld: @escaping @MainActor () async throws
            -> WhereFlyoverWorld = WhereFlyoverWorld.build)
        {
            self.buildWorld = buildWorld
        }

        func load() async {
            guard case .idle = state else { return }
            state = .loading
            do {
                let world = try await buildWorld()
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
