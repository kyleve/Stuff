#if DEBUG
    import PeriscopeCore
    import SwiftUI

    struct PeriscopePreviewFixture {
        let store: PeriscopeStore
        let scope: LogScope
        let event: StoredLogEvent
    }

    struct PeriscopeToolsPreview<Content: View>: View {
        private enum FixtureError: Error { case missingSeededEvent }

        @ViewBuilder let content: (PeriscopePreviewFixture) -> Content
        @State private var result: Result<PeriscopePreviewFixture, Error>?

        var body: some View {
            NavigationStack {
                switch result {
                    case nil: ProgressView()
                    case let .failure(error): Text(error.localizedDescription)
                    case let .success(fixture): content(fixture)
                }
            }
            .periscopeBroadwayRoot()
            .task { await load() }
        }

        private func load() async {
            do {
                let store = try await PeriscopeStore.make(
                    storage: .inMemory,
                    session: .current(attributes: [:]),
                )
                let scope = LogScope.root(named: "Preview")
                await store.defineScopes([scope])
                let spanID = SpanID()
                let name = "Refresh catalog"
                let start = Date(timeIntervalSinceReferenceDate: 100)
                await store.write([
                    LogRecord(date: start, event: SpanBegan(
                        spanID: .restricted(.identifier, spanID),
                        name: .restricted(.technicalState, name),
                        lifetimeMode: .restricted(.technicalState, .scoped),
                        budget: .shared(.duration, nil),
                        relaunchPolicy: .shared(.category, .endsWithProcess),
                    ), scopes: [scope.id]),
                    LogRecord(date: start.addingTimeInterval(1), event: SpanEnded(
                        spanID: .restricted(.identifier, spanID),
                        name: .restricted(.technicalState, name),
                        duration: .shared(.duration, .seconds(1)),
                        exitMode: .shared(.category, .success),
                        exitReason: .restricted(.errorDetails, nil),
                    ), scopes: [scope.id]),
                ])
                if let event = try await store.events(matching: LogQuery()).first {
                    result = .success(PeriscopePreviewFixture(
                        store: store,
                        scope: scope,
                        event: event,
                    ))
                } else {
                    result = .failure(FixtureError.missingSeededEvent)
                }
            } catch {
                result = .failure(error)
            }
        }
    }

    #Preview {
        PeriscopeToolsPreview { fixture in PeriscopeViewer(store: fixture.store) }
    }
#endif
