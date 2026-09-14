import PortholeCore
import SwiftUI

struct PortholeSourceBrowserView: View {
    let controller: PortholePresentationController
    @State private var search = ""

    var body: some View {
        List {
            switch controller.loadState {
                case .idle, .loading: ProgressView("Loading installed source…")
                case let .failed(message): Text(message)
                case let .loaded(snapshot):
                    Section("Source from this installed build") {
                        ForEach(snapshot.sources.filter {
                            search.isEmpty || $0.path.localizedStandardContains(search) || $0
                                .content.localizedStandardContains(search)
                        }) { source in
                            NavigationLink(source.path) { PortholeSourceView(file: source) }
                        }
                    }
            }
        }
        .navigationTitle("Source")
        .searchable(text: $search, prompt: "Path or source text")
    }
}
