import PortholeCore
import SwiftUI

/// A paged table for a data source, with a live tail toggle for subscribable
/// sources.
struct SourceTableView: View {
    @State var model: SourceTableModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).padding()
            }
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        ForEach(model.columns, id: \.self) { column in
                            Text(column).font(.caption.bold())
                        }
                    }
                    Divider()
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(model.columns, id: \.self) { column in
                                Text(Rendering.cell(row[column]))
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding()
            }
            if model.canLoadMore {
                Button("Load More") { Task { await model.loadMore() } }
                    .padding(8)
            }
        }
        .overlay {
            if model.isLoading, model.rows.isEmpty {
                ProgressView()
            } else if model.rows.isEmpty, model.errorMessage == nil {
                ContentUnavailableView("No rows", systemImage: "tablecells")
            }
        }
        .navigationTitle(model.descriptor.title)
        .toolbar {
            if model.descriptor.supportsSubscription {
                ToolbarItem {
                    Toggle("Live", isOn: $model.isLive)
                        .toggleStyle(.switch)
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.loadFirstPage() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await model.loadFirstPage() }
        .onDisappear { model.teardown() }
    }
}
