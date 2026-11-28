import PeriscopeCore
import SFSafeSymbols
import SwiftUI

/// The events in one scope's subtree, newest first — the drill-in from the
/// hierarchy browser. Rows indent by their depth below the viewed scope, so
/// nested sub-scopes read as a tree; each links into the standard detail.
///
/// Reuses ``LogInspectorModel`` (a subtree query with live refresh) since it
/// already merges a scope subtree newest-first.
struct ScopeEventsView: View {
    private let store: PeriscopeStore
    private let scopeID: ScopeID
    private let scopePath: String
    @State private var model: LogInspectorModel

    init(store: PeriscopeStore, scopeID: ScopeID, scopePath: String) {
        self.store = store
        self.scopeID = scopeID
        self.scopePath = scopePath
        _model = State(initialValue: LogInspectorModel(
            store: store,
            inspectedScopes: [scopeID],
            limit: 500,
        ))
    }

    /// The identity of this view's inputs — re-keying the task rebinds the
    /// model when either changes in place.
    private struct Inputs: Equatable {
        let store: ObjectIdentifier
        let scope: ScopeID
    }

    var body: some View {
        ScopeEventListContent(
            model: model,
            store: store,
            emptyDescription: "Nothing has been logged in this scope's subtree.",
            depth: { model.depth(of: $0, below: scopeID) },
        )
        .navigationTitle(scopePath.isEmpty ? "Scope" : scopePath)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.logRowDensity, .load(from: .standard))
        .periscopeBroadwayRoot()
        .task(id: Inputs(store: ObjectIdentifier(store), scope: scopeID)) {
            if model.store !== store || model.inspectedScopes != [scopeID] {
                model = LogInspectorModel(
                    store: store,
                    inspectedScopes: [scopeID],
                    limit: 500,
                )
            }
            await model.run()
        }
    }
}

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            ScopeEventsView(
                store: fixture.store,
                scopeID: fixture.scope.id,
                scopePath: fixture.scope.name,
            )
        }
    }
#endif
