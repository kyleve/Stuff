import CodeGraphModel
import SwiftUI

/// Details for the selected node: its declaration and the relationships that
/// flow in and out of it, each row jumping to the other end.
struct InspectorView: View {
    let model: GraphViewModel
    let nodeID: String

    var body: some View {
        if let node = model.node(nodeID) {
            List {
                declaration(node)
                relationships(
                    title: "Outgoing",
                    edges: model.outgoing(node.id),
                    otherID: { $0.target },
                    leadingIsKind: true,
                )
                relationships(
                    title: "Incoming",
                    edges: model.incoming(node.id),
                    otherID: { $0.source },
                    leadingIsKind: false,
                )
            }
            .listStyle(.sidebar)
        } else {
            ContentUnavailableView("Nothing selected", systemImage: "cursorarrow.rays")
        }
    }

    private func declaration(_ node: Node) -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: GraphStyle.symbol(for: node.kind))
                    .foregroundStyle(GraphStyle.color(for: node.kind))
                Text(node.name).font(.headline)
            }
            LabeledContent("Kind", value: node.kind.rawValue)
            LabeledContent("Module", value: node.module)
            LabeledContent("Origin", value: node.origin.rawValue)
            if node.isGeneric {
                LabeledContent("Generic", value: "yes")
            }
            if node.kind.isType, model.memberCount(node.id) > 0 {
                LabeledContent("Members", value: model.memberCount(node.id).formatted())
            }
            if let file = node.file {
                LabeledContent("File") {
                    Text(node.line.map { "\(file):\($0)" } ?? file)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func relationships(
        title: String,
        edges: [GraphEdge],
        otherID: @escaping (GraphEdge) -> String,
        leadingIsKind: Bool,
    ) -> some View {
        let grouped = Dictionary(grouping: edges, by: \.kind)
            .sorted { $0.key.rawValue < $1.key.rawValue }
        if !edges.isEmpty {
            Section("\(title) (\(edges.count))") {
                ForEach(grouped, id: \.key) { kind, kindEdges in
                    ForEach(kindEdges) { edge in
                        relationshipRow(
                            edge: edge,
                            otherID: otherID(edge),
                            showKind: leadingIsKind ? kind : kind,
                        )
                    }
                }
            }
        }
    }

    private func relationshipRow(
        edge: GraphEdge,
        otherID: String,
        showKind: EdgeKind,
    ) -> some View {
        Button {
            model.select(otherID)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(GraphStyle.color(for: showKind))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.node(otherID)?.name ?? otherID)
                        .lineLimit(1)
                    Text(showKind.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if edge.count > 1 {
                    Text("×\(edge.count)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
