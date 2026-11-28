import SFSafeSymbols
import SwiftUI

/// Recovery surface for a configured SwiftData source whose container cannot
/// open under the current schema.
struct InspectorUnavailableSwiftDataView: View {
    let source: InspectorConfiguration.SwiftDataSource
    let model: InspectorModel

    @State private var isConfirmingErase = false

    var body: some View {
        ContentUnavailableView {
            Label("SwiftData Unavailable", systemSymbol: .exclamationmarkTriangle)
        } description: {
            Text(model.swiftDataFailures[source.id] ?? "The store could not be opened.")
        } actions: {
            if model.erasingSwiftDataSources.contains(source.id) {
                ProgressView("Deleting Store…")
            } else if model.canEraseUnreadableStore(id: source.id) {
                InspectorDeleteButton(
                    title: "Delete Unreadable Store",
                    symbol: .trash,
                    question: "Delete the unreadable SwiftData store?",
                    confirmation: "Delete Store",
                    message: """
                    The database, its recovery files, and external data will be permanently \
                    deleted and this source will be removed from Inspector until the app is \
                    relaunched. This cannot be undone.
                    """,
                    isConfirming: $isConfirmingErase,
                ) {
                    eraseStore()
                }
            }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eraseStore() {
        Task {
            _ = await model.eraseUnreadableStore(id: source.id)
        }
    }
}
