import SwiftUI
import UIKit

/// The per-entity detail: a lazily-rendered table of every row's columns. The
/// header pins while the rows scroll vertically, the whole grid scrolls
/// horizontally for wide schemas, and it is searchable across all cell values.
struct EntityTableView: View {
    let model: SwiftDataInspectorModel
    let entity: InspectorEntity

    /// The rows loaded so far. Starts with the first page and grows as the user
    /// taps "load more"; `persistentID` keeps identities stable across appends.
    @State private var rows: [InspectorRow] = []
    @State private var totalCount = 0
    @State private var characterCounts: [String: Int] = [:]
    @State private var hasLoaded = false
    @State private var isLoadingMore = false
    @State private var searchText = ""
    @State private var selectedRow: InspectorRow?

    private let columnSpacing: CGFloat = 20
    private let minColumnWidth: CGFloat = 48
    /// Caps how wide any single column grows, so one long blob can't push the
    /// rest off-screen.
    private let maxColumnWidth: CGFloat = 280

    var body: some View {
        Group {
            if hasLoaded {
                content
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search rows")
        // Load the first page once; drilling into a row and back keeps the rows
        // (and any "load more" pages) already on screen. Pull-to-refresh resets.
        .task { if !hasLoaded { await load() } }
        .refreshable { await load() }
        .navigationDestination(item: $selectedRow) { row in
            RowDetailView(model: model, entity: entity, row: row)
        }
    }

    /// Fetch the first page, replacing whatever is loaded (initial load and
    /// pull-to-refresh).
    private func load() async {
        let set = await model.rows(for: entity, offset: 0)
        rows = set.rows
        totalCount = set.totalCount
        characterCounts = set.columnCharacterCounts
        hasLoaded = true
    }

    /// Fetch the next page and append it, merging the new page's per-column
    /// character counts so columns don't shrink as more rows arrive.
    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        let set = await model.rows(for: entity, offset: rows.count)
        rows.append(contentsOf: set.rows)
        totalCount = set.totalCount
        characterCounts = Self.mergedCounts(characterCounts, adding: set.columnCharacterCounts)
        isLoadingMore = false
    }

    private var canLoadMore: Bool {
        rows.count < totalCount
    }

    @ViewBuilder
    private var content: some View {
        if entity.columns.isEmpty {
            ContentUnavailableView(
                "No Columns",
                systemImage: "rectangle.split.3x1",
                description: Text("This entity exposes no inspectable attributes."),
            )
        } else if rows.isEmpty {
            ContentUnavailableView(
                "No Rows",
                systemImage: "tray",
                description: Text("This entity has no saved rows."),
            )
        } else {
            let visible = filtered(rows)
            VStack(spacing: 0) {
                if visible.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    table(rows: visible)
                }
                footerBar
            }
        }
    }

    private func table(rows: [InspectorRow]) -> some View {
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

    /// The whole row is a button into the per-row detail. Cell text selection
    /// moves to the detail view, where values are shown in full; here a tap drills
    /// in (selection would otherwise swallow the tap).
    private func cellRow(_ row: InspectorRow) -> some View {
        Button {
            selectedRow = row
        } label: {
            HStack(spacing: columnSpacing) {
                ForEach(entity.columns, id: \.self) { column in
                    Text(row.cells[column] ?? "—")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(row.cells[column] == nil ? .tertiary : .primary)
                        .frame(width: width(of: column), alignment: .leading)
                }
            }
            .contentShape(.rect)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    /// The pinned bottom bar: how many rows are loaded versus the total, plus a
    /// "Load more" button (or a spinner while a page is in flight) when more
    /// rows remain. With no `rowLimit` everything loads at once, so the button
    /// never appears.
    private var footerBar: some View {
        HStack(spacing: 12) {
            Text(countSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if canLoadMore {
                if isLoadingMore {
                    ProgressView()
                } else {
                    Button("Load more") { Task { await loadMore() } }
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var countSummary: String {
        if canLoadMore {
            "Showing \(rows.count) of \(totalCount) rows"
        } else {
            "\(totalCount) row\(totalCount == 1 ? "" : "s")"
        }
    }

    /// Cells are monospaced, so a column's width is the longest string in it
    /// (header or any cell) times the fixed character advance, clamped to a
    /// sensible range. The per-cell character counting is done off-main by the
    /// reader (`columnCharacterCounts`); here it's an O(1) lookup, and it's
    /// derived from the full page so columns don't reflow while searching.
    private func width(of column: String) -> CGFloat {
        let characters = max(column.count, characterCounts[column] ?? 0)
        let raw = CGFloat(characters) * Self.characterWidth + 12
        return min(max(raw, minColumnWidth), maxColumnWidth)
    }

    private func filtered(_ rows: [InspectorRow]) -> [InspectorRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Combine two pages' per-column character counts, keeping the larger so a
    /// column already sized for an earlier page never shrinks when more arrive.
    private static func mergedCounts(
        _ base: [String: Int],
        adding addition: [String: Int],
    ) -> [String: Int] {
        base.merging(addition) { max($0, $1) }
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
