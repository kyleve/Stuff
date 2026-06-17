import CodeGraphModel
import SwiftUI

/// Placeholder rendering that proves a graph loaded and hot-reloads. The
/// interactive canvas replaces this in a later step.
struct GraphSummaryView: View {
    let graph: CodeGraph

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Modules", value: graph.modules.count.formatted())
                LabeledContent("Nodes", value: graph.nodes.count.formatted())
                LabeledContent("Edges", value: graph.edges.count.formatted())
                if let commit = graph.commit {
                    LabeledContent("Commit", value: String(commit.prefix(8)))
                }
                LabeledContent(
                    "Generated",
                    value: graph.generatedAt.formatted(date: .abbreviated, time: .shortened),
                )
            }

            Section("Modules") {
                ForEach(graph.modules.sorted { $0.name < $1.name }) { module in
                    HStack {
                        Text(module.name)
                        Spacer()
                        Text(module.kind.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
