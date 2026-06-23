import SwiftUI

/// The per-entity detail: a scrollable table of every row's columns. Scrolls
/// both ways (wide schemas scroll horizontally) and is searchable across all
/// cell values.
struct EntityTableView: View {
    let model: SwiftDataInspectorModel
    let entity: InspectorEntity

    @State private var rowSet: InspectorRowSet?
    @State private var searchText = ""

    /// Caps how wide any single column grows, so one long blob can't push the
    /// rest off-screen.
    private let maxColumnWidth: CGFloat = 280

    var body: some View {
        Group {
            if let rowSet {
                content(for: rowSet)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search rows")
        .task { rowSet = model.rows(for: entity) }
    }

    @ViewBuilder
    private func content(for rowSet: InspectorRowSet) -> some View {
        if entity.columns.isEmpty {
            ContentUnavailableView(
                "No Columns",
                systemImage: "rectangle.split.3x1",
                description: Text("This entity exposes no inspectable attributes."),
            )
        } else if rowSet.rows.isEmpty {
            ContentUnavailableView(
                "No Rows",
                systemImage: "tray",
                description: Text("This entity has no saved rows."),
            )
        } else {
            let rows = filtered(rowSet.rows)
            if rows.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                table(rows: rows, footer: footer(for: rowSet))
            }
        }
    }

    private func table(rows: [InspectorRow], footer: String?) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    ForEach(entity.columns, id: \.self) { column in
                        Text(column)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: maxColumnWidth, alignment: .leading)
                    }
                }
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        ForEach(entity.columns, id: \.self) { column in
                            Text(row.cells[column] ?? "—")
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .foregroundStyle(row.cells[column] == nil ? .tertiary : .primary)
                                .frame(maxWidth: maxColumnWidth, alignment: .leading)
                        }
                    }
                }
            }
            .padding()
            .safeAreaInset(edge: .bottom) {
                if let footer {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        }
    }

    private func filtered(_ rows: [InspectorRow]) -> [InspectorRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func footer(for rowSet: InspectorRowSet) -> String? {
        guard rowSet.isTruncated else { return nil }
        return "Showing first \(rowSet.rows.count) of \(rowSet.totalCount) rows"
    }
}

#if DEBUG
    #Preview {
        InspectorPreviewData.tablePreview()
    }
#endif
