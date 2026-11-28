import PeriscopeCore
import SFSafeSymbols
import SwiftUI

/// The sheet log view mode presents: the inspected context's events, newest
/// first, each linking into the standard event detail (and from there the
/// tracer).
struct LogInspectorView: View {
    let store: PeriscopeStore
    let scopes: [ScopeID]
    let limit: Int

    @State private var model: LogInspectorModel
    @Environment(\.dismiss) private var dismiss

    init(store: PeriscopeStore, scopes: [ScopeID], limit: Int) {
        self.store = store
        self.scopes = scopes
        self.limit = limit
        _model = State(initialValue: LogInspectorModel(
            store: store,
            inspectedScopes: scopes,
            limit: limit,
        ))
    }

    /// The identity of this view's inputs — re-keying the task rebinds the
    /// model when any changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let scopes: [ScopeID]
        let limit: Int
    }

    var body: some View {
        ScopeEventListContent(
            model: model,
            store: store,
            emptyDescription: "Nothing has been logged in this element's scopes.",
        )
        .navigationTitle("Element Logs")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.logRowDensity, .load(from: .standard))
        .periscopeBroadwayRoot()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task(id: Inputs(store: ObjectIdentifier(store), scopes: scopes, limit: limit)) {
            if model.store !== store || model.inspectedScopes != scopes
                || model.limit != limit
            {
                model = LogInspectorModel(
                    store: store,
                    inspectedScopes: scopes,
                    limit: limit,
                )
            }
            await model.run()
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            LogInspectorView(store: fixture.store, scopes: [fixture.scope.id], limit: 100)
        }
    }
#endif
