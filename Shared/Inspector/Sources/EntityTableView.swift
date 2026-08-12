import SFSafeSymbols
import SwiftUI
import UIKit

/// The per-entity detail: a lazily-rendered table of every row's columns. The
/// header pins while the rows scroll vertically, the whole grid scrolls
/// horizontally for wide schemas, and it is searchable across all cell values.
struct EntityTableView: View {
    let model: InspectorSwiftDataModel
    let entity: InspectorEntity

    /// The rows currently shown: the store's first `pageCount` pages. "Load more"
    /// bumps `pageCount` and re-fetches the whole prefix in one query, then
    /// replaces this wholesale — so the visible rows always come from a single
    /// consistent fetch and can never overlap or skip, even without a sort.
    /// `persistentID` keeps identities (and scroll position) stable across the
    /// replace.
    @State private var rows: [InspectorRow] = []
    /// Longest cell string length per column, computed off-main by the reader.
    @State private var characterCounts: [String: Int] = [:]
    @State private var totalCount = 0
    @State private var hasLoaded = false
    @State private var isLoadingMore = false
    @State private var searchText = ""
    @State private var selectedRow: InspectorRow?
    /// How many `rowLimit`-sized pages to fetch. Starts at one; "load more"
    /// increments it. With no `rowLimit` every row loads at once and this is
    /// irrelevant.
    @State private var pageCount = 1
    @State private var isConfirmingDeleteAll = false

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
        .onChange(of: model.mutationGeneration) {
            Task { await load() }
        }
        .navigationDestination(item: $selectedRow) { row in
            RowDetailView(model: model, entity: entity, row: row)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    "Delete All Rows",
                    systemSymbol: .trash,
                    role: .destructive,
                ) {
                    isConfirmingDeleteAll = true
                }
                .disabled(totalCount == 0)
                .confirmationDialog(
                    "Delete every \(entity.name) row?",
                    isPresented: $isConfirmingDeleteAll,
                    titleVisibility: .visible,
                ) {
                    Button("Delete All Rows", role: .destructive) {
                        Task {
                            if await model.deleteAllRows(from: entity) {
                                pageCount = 1
                                await load()
                            }
                        }
                    }
                } message: {
                    Text(
                        "SwiftData relationship delete rules will be applied. This cannot be undone.",
                    )
                }
            }
        }
    }

    /// Fetch the first `pageCount` pages in one query and show them. Used for the
    /// initial load and pull-to-refresh, so refresh keeps whatever the user had
    /// expanded to.
    private func load() async {
        do {
            let set = try await model.rows(for: entity, pageCount: pageCount)
            rows = set.rows
            characterCounts = set.columnCharacterCounts
            totalCount = set.totalCount
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            model.report(error)
        }
    }

    /// Grow the visible window by one page and re-fetch the whole prefix in a
    /// single query, replacing the current rows. The existing rows stay on screen
    /// while the larger fetch is in flight, and their stable ids keep the scroll
    /// position when the new, longer page arrives.
    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let set = try await model.rows(for: entity, pageCount: pageCount + 1)
            pageCount += 1
            rows = set.rows
            characterCounts = set.columnCharacterCounts
            totalCount = set.totalCount
        } catch is CancellationError {
            return
        } catch {
            model.report(error)
        }
    }

    private var canLoadMore: Bool {
        rows.count < totalCount
    }

    @ViewBuilder
    private var content: some View {
        if entity.columns.isEmpty {
            ContentUnavailableView(
                "No Columns",
                systemSymbol: .rectangleSplit3x1,
                description: Text("This entity exposes no inspectable attributes."),
            )
        } else if rows.isEmpty {
            ContentUnavailableView(
                "No Rows",
                systemSymbol: .tray,
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
    /// reader (`columnCharacterCounts`); here it's an O(1) lookup.
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
