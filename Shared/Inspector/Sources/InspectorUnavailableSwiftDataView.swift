import SwiftUI

/// Recovery surface for a configured SwiftData source whose container cannot
/// open under the current schema.
struct InspectorUnavailableSwiftDataView: View {
    let source: InspectorConfiguration.SwiftDataSource
    let model: InspectorModel

    @State private var isConfirmingErase = false

    var body: some View {
        ContentUnavailableView {
            Label("SwiftData Unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.swiftDataFailures[source.id] ?? "The store could not be opened.")
        } actions: {
            if model.erasingSwiftDataSources.contains(source.id) {
                ProgressView("Deleting Store…")
            } else if model.canEraseUnreadableStore(id: source.id) {
                Button(
                    "Delete Unreadable Store",
                    systemImage: "trash",
                    role: .destructive,
                ) {
                    isConfirmingErase = true
                }
                .confirmationDialog(
                    "Delete the unreadable SwiftData store?",
                    isPresented: $isConfirmingErase,
                    titleVisibility: .visible,
                ) {
                    Button("Delete Store", role: .destructive, action: eraseStore)
                } message: {
                    Text(
                        """
                        The database, its recovery files, and external data will be permanently \
                        deleted. Inspector will then create a new empty store. This cannot be undone.
                        """,
                    )
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
