import PortholeCore
import SFSafeSymbols
import SwiftUI

/// A directed neighborhood with navigable context nodes, sized by its content.
struct PortholeContextGraphView: View {
    let graph: PortholeContextGraph
    let navigation: PortholeEvidenceNavigation
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
            ForEach(graph.incoming) { edge in
                PortholeEvidenceLink(reference: edge.reference, navigation: navigation)
                    .buttonStyle(.bordered)
                Label(edge.relation, systemSymbol: .arrowDown).font(.caption)
            }
            VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                Label(graph.context.title, systemSymbol: .viewfinder).font(.headline)
                Text("Scope: \(graph.context.scope.id.rawValue)").font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            ForEach(graph.outgoing) { edge in
                VStack(alignment: .leading, spacing: stylesheet.row.spacing) {
                    Label(edge.relation, systemSymbol: .arrowDown).font(.caption)
                    PortholeEvidenceLink(reference: edge.reference, navigation: navigation)
                        .buttonStyle(.bordered)
                }
                .padding(.leading, stylesheet.row.padding)
            }
            if graph.incoming.isEmpty, graph.outgoing.isEmpty {
                Text("No relationships were recorded for this context.").foregroundStyle(.secondary)
            }
        }
    }
}
