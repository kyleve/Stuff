import SwiftUI
import UIKit

/// The per-entity detail: a lazily-rendered table of every row's columns. The
/// header pins while the rows scroll vertically, the whole grid scrolls
/// horizontally for wide schemas, and it is searchable across all cell values.
struct EntityTableView: View {
    let model: SwiftDataInspectorModel
    let entity: InspectorEntity

    /// The rows currently shown: the store's first `pageCount` pages. "Load more"
    /// bumps `pageCount` and re-fetches the whole prefix in one query, then
    /// replaces this wholesale — so the visible rows always come from a single
    /// consistent fetch and can never overlap or skip, even without a sort.
    /// `persistentID` keeps identities (and scroll position) stable across the
    /// replace.
    @State private var rows: [InspectorRow] = []
    @State private var totalCount = 0
    @State private var hasLoaded = false
    @State private var isLoadingMore = false
    @State private var searchText = ""
    @State private var selectedRow: InspectorRow?
    /// How many `rowLimit`-sized pages to fetch. Starts at one; "load more"
    /// increments it. With no `rowLimit` every row loads at once and this is
    /// irrelevant.
    @State private var pageCount = 1

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
        // Load once; drilling into a row and back keeps the rows (and any
        // "load more" pages) already on screen. Pull-to-refresh re-reads the
        // same number of pages from a fresh context.
        .task { if !hasLoaded { await load() } }
        .refreshable { await load() }
        .navigationDestination(item: $selectedRow) { row in
            RowDetailView(model: model, entity: entity, row: row)
        }
    }

    /// Fetch the first `pageCount` pages in one query and show them. Used for the
    /// initial load and pull-to-refresh, so refresh keeps whatever the user had
    /// expanded to.
    private func load() async {
        let set = await model.rows(for: entity, pageCount: pageCount)
        rows = set.rows
        totalCount = set.totalCount
        hasLoaded = true
    }

    /// Grow the visible window by one page and re-fetch the whole prefix in a
    /// single query, replacing the current rows. The existing rows stay on screen
    /// while the larger fetch is in flight, and their stable ids keep the scroll
    /// position when the new, longer page arrives.
    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let set = await model.rows(for: entity, pageCount: pageCount + 1)
        pageCount += 1
        rows = set.rows
        totalCount = set.totalCount
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

    /// Cells are monospaced. Width is measured from the header and every loaded
    /// cell string in the column (not a character-count × glyph-width heuristic),
    /// then clamped to a sensible range.
    private func width(of column: String) -> CGFloat {
        var maxWidth = measure(column)
        for row in rows {
            if let cell = row.cells[column] {
                maxWidth = max(maxWidth, measure(cell))
            }
        }
        return min(max(maxWidth + 12, minColumnWidth), maxColumnWidth)
    }

    private func measure(_ string: String) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: Self.monospacedFont]).width
    }

    private func filtered(_ rows: [InspectorRow]) -> [InspectorRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private static let monospacedFont: UIFont = .monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
        weight: .regular,
    )
}

#if DEBUG
    #Preview {
        InspectorPreviewData.tablePreview()
    }
#endif
