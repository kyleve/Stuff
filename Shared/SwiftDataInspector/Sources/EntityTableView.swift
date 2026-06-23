import SwiftUI
import UIKit

/// The per-entity detail: a lazily-rendered table of every row's columns. The
/// header pins while the rows scroll vertically, the whole grid scrolls
/// horizontally for wide schemas, and it is searchable across all cell values.
struct EntityTableView: View {
    let model: SwiftDataInspectorModel
    let entity: InspectorEntity

    @State private var rowSet: InspectorRowSet?
    @State private var widths: [String: CGFloat] = [:]
    @State private var searchText = ""

    private let columnSpacing: CGFloat = 20
    private let minColumnWidth: CGFloat = 48
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
        .task { load() }
        .refreshable { load() }
    }

    private func load() {
        let set = model.rows(for: entity)
        rowSet = set
        widths = computeWidths(for: set.rows)
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
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(rows) { row in
                            cellRow(row)
                            Divider()
                        }
                    } header: {
                        headerRow
                    }
                }
                .padding(.horizontal)
            }
            if let footer {
                footerBar(footer)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            ForEach(entity.columns, id: \.self) { column in
                Text(column)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width(of: column), alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func cellRow(_ row: InspectorRow) -> some View {
        HStack(spacing: columnSpacing) {
            ForEach(entity.columns, id: \.self) { column in
                Text(row.cells[column] ?? "—")
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .foregroundStyle(row.cells[column] == nil ? .tertiary : .primary)
                    .frame(width: width(of: column), alignment: .leading)
            }
        }
        .padding(.vertical, 6)
    }

    private func footerBar(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.bar)
    }

    private func width(of column: String) -> CGFloat {
        widths[column] ?? maxColumnWidth
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

    /// Cells are monospaced, so a column's width is derived from the longest
    /// string in it (header or any cell) times the fixed character advance,
    /// clamped to a sensible range. Computed once per load from the full page so
    /// columns don't reflow while searching.
    private func computeWidths(for rows: [InspectorRow]) -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for column in entity.columns {
            var maxCharacters = column.count
            for row in rows {
                maxCharacters = max(maxCharacters, (row.cells[column] ?? "—").count)
            }
            let raw = CGFloat(maxCharacters) * Self.characterWidth + 12
            result[column] = min(max(raw, minColumnWidth), maxColumnWidth)
        }
        return result
    }

    private static let characterWidth: CGFloat = {
        let font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
            weight: .regular,
        )
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()
}

#if DEBUG
    #Preview {
        InspectorPreviewData.tablePreview()
    }
#endif
