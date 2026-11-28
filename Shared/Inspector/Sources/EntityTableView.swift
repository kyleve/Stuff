import SFSafeSymbols
import SwiftUI

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

    var body: some View {
        Group {
            if hasLoaded {
                EntityTableContent(
                    columns: .init(names: entity.columns, characterCounts: characterCounts),
                    hasRows: !rows.isEmpty,
                    visibleRows: filtered(rows),
                    searchText: searchText,
                    select: { selectedRow = $0 },
                    footer: EntityTableFooter(
                        countSummary: countSummary,
                        canLoadMore: canLoadMore,
                        isLoadingMore: isLoadingMore,
                        loadMore: loadMore,
                    ),
                )
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
        .task {
            if !hasLoaded {
                await load()
            }
        }
        .refreshable { await load() }
        .onChange(of: model.mutationTrigger) {
            Task { await load() }
        }
        .navigationDestination(item: $selectedRow) { row in
            RowDetailView(model: model, entity: entity, row: row)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InspectorDeleteButton(
                    title: "Delete All Rows",
                    symbol: .trash,
                    question: "Delete every \(entity.name) row?",
                    message: "SwiftData relationship delete rules will be applied. This cannot be undone.",
                    isDisabled: totalCount == 0,
                    isConfirming: $isConfirmingDeleteAll,
                ) {
                    Task {
                        if await model.deleteAllRows(from: entity) {
                            pageCount = 1
                            await load()
                        }
                    }
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

    private var countSummary: String {
        if canLoadMore {
            "Showing \(rows.count) of \(totalCount) rows"
        } else {
            "\(totalCount) row\(totalCount == 1 ? "" : "s")"
        }
    }

    private func filtered(_ rows: [InspectorRow]) -> [InspectorRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            row.cells.values.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

/// The pinned bottom bar: how many rows are loaded versus the total, plus a
/// "Load more" button (or a spinner while a page is in flight) when more
/// rows remain. With no `rowLimit` everything loads at once, so the button
/// never appears.
struct EntityTableFooter: View {
    let countSummary: String
    let canLoadMore: Bool
    let isLoadingMore: Bool
    let loadMore: () async -> Void

    var body: some View {
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
}

#if DEBUG
    #Preview {
        InspectorPreviewData.tablePreview()
    }
#endif
