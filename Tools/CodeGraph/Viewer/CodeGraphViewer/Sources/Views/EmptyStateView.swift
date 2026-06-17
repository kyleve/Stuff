import SwiftUI

struct EmptyStateView: View {
    let error: String?
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("No graph loaded")
                    .font(.title2.weight(.semibold))
                Text(
                    "Open a graph.json produced by code-graph-extract to explore the repository's types and relationships.",
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            }
            VStack(spacing: 10) {
                Button(action: onOpen) {
                    Label("Open graph.json", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("or drag a graph.json onto the window")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
