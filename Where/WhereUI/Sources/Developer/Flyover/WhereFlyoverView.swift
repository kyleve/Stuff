#if DEBUG
    import Flyover
    import SFSafeSymbols
    import SwiftUI

    /// Where's DEBUG-only host for the generic Flyover browser.
    struct WhereFlyoverView: View {
        @State private var loader = WhereFlyoverLoader()

        var body: some View {
            Group {
                switch loader.state {
                    case .idle, .loading:
                        ProgressView("Building in-memory app…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .loaded(catalog):
                        FlyoverView(catalog: catalog)
                    case let .failed(message):
                        FlyoverLoadFailure(message: message, retry: loader.retry)
                }
            }
            .task(id: loader.retryTrigger) {
                await loader.load()
            }
        }
    }

    #Preview {
        WhereFlyoverView()
    }

    private struct FlyoverLoadFailure: View {
        let message: String
        let retry: () -> Void

        var body: some View {
            ContentUnavailableView {
                Label("Flyover failed to load", systemSymbol: .exclamationmarkTriangle)
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: retry)
            }
        }
    }
#endif
