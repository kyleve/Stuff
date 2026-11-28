import SFSafeSymbols
import SwiftUI
import UIKit

struct EntityTableContent: View {
    let columns: EntityTableColumns
    let hasRows: Bool
    let visibleRows: [InspectorRow]
    let searchText: String
    let select: (InspectorRow) -> Void
    let footer: EntityTableFooter

    var body: some View {
        if columns.names.isEmpty {
            ContentUnavailableView(
                "No Columns",
                systemSymbol: .rectangleSplit3x1,
                description: Text("This entity exposes no inspectable attributes."),
            )
        } else if !hasRows {
            ContentUnavailableView(
                "No Rows",
                systemSymbol: .tray,
                description: Text("This entity has no saved rows."),
            )
        } else {
            VStack(spacing: 0) {
                if visibleRows.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EntityTableGrid(columns: columns, rows: visibleRows, select: select)
                }
                footer
            }
        }
    }
}

private struct EntityTableGrid: View {
    let columns: EntityTableColumns
    let rows: [InspectorRow]
    let select: (InspectorRow) -> Void

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        EntityTableRowButton(columns: columns, row: row, select: select)
                        Divider()
                    }
                } header: {
                    EntityTableHeader(columns: columns)
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct EntityTableHeader: View {
    let columns: EntityTableColumns

    var body: some View {
        HStack(spacing: columns.spacing) {
            ForEach(columns.names, id: \.self) { column in
                Text(column)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: columns.width(of: column), alignment: .leading)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// The whole row is a button into the per-row detail. Cell text selection
/// moves to the detail view, where values are shown in full; here a tap drills
/// in (selection would otherwise swallow the tap).
private struct EntityTableRowButton: View {
    let columns: EntityTableColumns
    let row: InspectorRow
    let select: (InspectorRow) -> Void

    var body: some View {
        Button {
            select(row)
        } label: {
            HStack(spacing: columns.spacing) {
                ForEach(columns.names, id: \.self) { column in
                    Text(row.cells[column] ?? "—")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(row.cells[column] == nil ? .tertiary : .primary)
                        .frame(width: columns.width(of: column), alignment: .leading)
                }
            }
            .contentShape(.rect)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
struct EntityTableColumns {
    let names: [String]
    let characterCounts: [String: Int]

    let spacing: CGFloat = 20
    private let minColumnWidth: CGFloat = 48
    /// Caps how wide any single column grows, so one long blob can't push the
    /// rest off-screen.
    private let maxColumnWidth: CGFloat = 280
    /// Cells are monospaced, so a column's width is the longest string in it
    /// (header or any cell) times the fixed character advance, clamped to a
    /// sensible range. The per-cell character counting is done off-main by the
    /// reader (`columnCharacterCounts`); here it's an O(1) lookup.
    func width(of column: String) -> CGFloat {
        let characters = max(column.count, characterCounts[column] ?? 0)
        let raw = CGFloat(characters) * Self.characterWidth + 12
        return min(max(raw, minColumnWidth), maxColumnWidth)
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
    #Preview { InspectorPreviewData.tablePreview() }
#endif
