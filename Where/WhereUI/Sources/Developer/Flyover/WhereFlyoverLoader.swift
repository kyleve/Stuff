#if DEBUG
    import Flyover
    import Observation

    /// Async load state for the separately built Flyover catalog.
    @MainActor
    @Observable
    final class WhereFlyoverLoader {
        enum LoadState {
            case idle
            case loading
            case loaded(FlyoverCatalog<WhereFlyoverScreenID>)
            case failed(String)
        }

        private(set) var state = LoadState.idle
        private(set) var request = 0

        func load() async {
            guard case .idle = state else {
                return
            }
            state = .loading
            do {
                let world = try await WhereFlyoverWorld.build()
                state = .loaded(WhereFlyoverCatalog.make(world: world))
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }

        func retry() {
            state = .idle
            request += 1
        }
    }
#endif
