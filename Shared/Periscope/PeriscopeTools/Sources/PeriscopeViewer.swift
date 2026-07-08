import PeriscopeCore
import SwiftUI

/// The latest-logs viewer: a reverse-chronological, searchable list over a
/// `PeriscopeStore`, filterable by level, event type, scope subtree, and
/// session, with NDJSON export for bug reports.
///
/// Designed to be pushed inside an existing `NavigationStack` (it sets a
/// navigation title and toolbar but does not create its own stack). A
/// developer surface — gate it behind `#if DEBUG` or a developer menu.
public struct PeriscopeViewer: View {
    private let store: PeriscopeStore
    private let title: String
    @State private var model: PeriscopeViewerModel
    @State private var export: NDJSONExport?
    @State private var exportFailed = false

    public init(store: PeriscopeStore, title: String = "Logs") {
        self.store = store
        self.title = title
        _model = State(initialValue: PeriscopeViewerModel(store: store))
    }

    public var body: some View {
        @Bindable var model = model
        content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    exportButton
                }
            }
            .searchable(text: $model.searchText)
            .sheet(item: $export) { export in
                NDJSONExportSheet(export: export)
            }
            .alert("Export Failed", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            }
            .task {
                await model.run()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView(
                    "Logs Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(reason),
                )
            case let .loaded(events) where events.isEmpty:
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("No stored events match the current filters."),
                )
            case let .loaded(events):
                List {
                    ForEach(events) { event in
                        NavigationLink {
                            LogEventDetailView(
                                event: event,
                                scopePath: model.scopePath(for: event),
                                store: store,
                            )
                        } label: {
                            LogEventRow(event: event, scopePath: model.scopePath(for: event))
                        }
                    }
                    if model.canLoadMore {
                        Button("Load More") {
                            Task { await model.loadMore() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
        }
    }

    private var filterMenu: some View {
        @Bindable var model = model
        return Menu {
            Picker("Level", selection: $model.minimumLevel) {
                Text("All Levels").tag(LogLevel?.none)
                ForEach(model.availableLevels, id: \.self) { level in
                    Text(level.displayName).tag(LogLevel?.some(level))
                }
            }
            Picker("Event", selection: $model.selectedEventName) {
                Text("All Events").tag(String?.none)
                ForEach(model.eventNames, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            Picker("Scope", selection: $model.selectedScope) {
                Text("All Scopes").tag(ScopeID?.none)
                ForEach(model.scopeChoices) { choice in
                    Text(choice.path).tag(ScopeID?.some(choice.id))
                }
            }
            Picker("Session", selection: $model.selectedSessionID) {
                Text("All Sessions").tag(UUID?.none)
                ForEach(model.sessions) { session in
                    Text(sessionLabel(session)).tag(UUID?.some(session.id))
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var exportButton: some View {
        Button {
            Task {
                do {
                    export = try await NDJSONExport(text: model.exportNDJSON())
                } catch {
                    exportFailed = true
                }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    private func sessionLabel(_ session: LogSession) -> String {
        let started = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(started) — v\(session.appVersion) (\(session.buildNumber))"
    }
}

/// A generated NDJSON export, presented in a share sheet.
struct NDJSONExport: Identifiable {
    let id = UUID()
    let text: String
}

private struct NDJSONExportSheet: View {
    let export: NDJSONExport

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(export.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("NDJSON Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: export.text, preview: SharePreview("Periscope Logs"))
                }
            }
        }
    }
}

private struct LogEventRow: View {
    let event: StoredLogEvent
    let scopePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LogLevelBadge(level: event.level)
                Text(event.eventName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(event.date, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(event.message)
                .font(.callout)
                .lineLimit(3)
            if !scopePath.isEmpty {
                Text(scopePath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The severity badge shared by the viewer, tracer, and inspector.
struct LogLevelBadge: View {
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
