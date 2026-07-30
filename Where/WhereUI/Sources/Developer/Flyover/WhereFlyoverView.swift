#if DEBUG
    import Flyover
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
                        ContentUnavailableView {
                            Label("Flyover failed to load", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("Try Again", action: loader.retry)
                        }
                }
            }
            .navigationBarBackButtonHidden(true)
            .task(id: loader.request) {
                await loader.load()
            }
        }
    }

    #Preview {
        WhereFlyoverView()
    }
#endif
