@_spi(Testing) import LogKit
import SwiftUI
import UIKit

/// A generic, read-only viewer over a ``LogStore``. Renders entries newest
/// first with a level badge, category, timestamp, and message, and offers
/// search, level/category filtering, share, and clear.
///
/// Designed to be pushed inside an existing `NavigationStack` (it sets a
/// navigation title and toolbar but does not create its own stack).
public struct LogViewer: View {
    private let configuration: LogViewerConfiguration
    @State private var model: LogViewerModel
    @State private var showClearConfirmation = false

    public init(configuration: LogViewerConfiguration) {
        self.configuration = configuration
        _model = State(initialValue: LogViewerModel(
            stores: configuration.stores,
            categoryDisplayName: configuration.categoryDisplayName,
        ))
    }

    public var body: some View {
        @Bindable var model = model
        content
            .navigationTitle(configuration.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Level", selection: $model.minimumLevel) {
                            ForEach(LogLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }

                        Picker("Category", selection: $model.selectedCategory) {
                            Text("All Categories").tag(String?.none)
                            ForEach(model.categories, id: \.self) { category in
                                Text(configuration.categoryDisplayName(category))
                                    .tag(String?.some(category))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(
                            item: LogExportItem(
                                entries: model.filteredEntries.reversed(),
                                categoryDisplayName: configuration.categoryDisplayName,
                            ),
                            preview: SharePreview("Logs"),
                        ) {
                            Label("Share Logs", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .confirmationDialog(
                        "Clear all captured logs?",
                        isPresented: $showClearConfirmation,
                        titleVisibility: .visible,
                    ) {
                        Button("Clear Logs", role: .destructive) { model.clear() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .searchable(text: $model.searchText)
    }

    @ViewBuilder
    private var content: some View {
        if model.isEmpty {
            ContentUnavailableView(
                "No Logs",
                systemImage: "doc.text.magnifyingglass",
                description: Text("Logs captured this session will appear here."),
            )
        } else if model.hasNoFilterMatches {
            ContentUnavailableView(
                "No Matching Logs",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try adjusting your filters or search."),
            )
        } else {
            List(model.filteredEntries) { entry in
                LogEntryRow(
                    entry: entry,
                    categoryName: configuration.categoryDisplayName(entry.category),
                )
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = entry.message
                    } label: {
                        Label("Copy Message", systemImage: "doc.on.doc")
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

/// Defers plain-text export until the share sheet requests the payload.
private struct LogExportItem: Transferable {
    let entries: [LogEntry]
    let categoryDisplayName: @Sendable (String) -> String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { item in
            LogViewerModel.formatExportText(
                entries: item.entries,
                categoryDisplayName: item.categoryDisplayName,
            )
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry
    let categoryName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LevelBadge(level: entry.level)
                Text(categoryName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(entry.message)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

private struct LevelBadge: View {
    let level: LogLevel

    var body: some View {
        Text(level.badgeLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(level.tint.opacity(0.18), in: .capsule)
            .foregroundStyle(level.tint)
    }
}

#if DEBUG
    #Preview {
        let store = LogStore()
        for index in 0 ..< 6 {
            let levels: [LogLevel] = [.debug, .info, .notice, .error, .fault]
            store.record(LogEntry(
                level: levels[index % levels.count],
                subsystem: "com.example.app",
                category: index.isMultiple(of: 2) ? "Networking" : "Persistence",
                message: "Sample log message #\(index) describing what happened.",
            ))
        }
        return NavigationStack {
            LogViewer(configuration: LogViewerConfiguration(store: store, title: "Logs"))
        }
    }
#endif
