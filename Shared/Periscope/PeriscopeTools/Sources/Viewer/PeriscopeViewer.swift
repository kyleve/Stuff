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
    private let defaults: UserDefaults
    @State private var model: PeriscopeViewerModel
    @State private var export: NDJSONExport?
    @State private var exportFailed = false
    @State private var density: PeriscopeStylesheet.Density

    public init(store: PeriscopeStore, title: String = "Logs") {
        self.init(store: store, title: title, defaults: .standard)
    }

    init(store: PeriscopeStore, title: String, defaults: UserDefaults) {
        self.store = store
        self.title = title
        self.defaults = defaults
        _model = State(initialValue: PeriscopeViewerModel(store: store))
        _density = State(initialValue: .load(from: defaults))
    }

    public var body: some View {
        TabView {
            Tab("Logs", systemImage: "list.bullet") {
                logsTab
            }
            Tab("Hierarchy", systemImage: "list.bullet.indent") {
                LogHierarchyView(store: store)
            }
        }
        .environment(\.logRowDensity, density)
        .onChange(of: density) { _, newValue in
            newValue.save(to: defaults)
        }
        .periscopeBroadwayRoot()
        // Keyed on the store's identity: swapping stores in place cancels the
        // old model's live stream and rebinds a fresh model — `State(initialValue:)`
        // alone would keep serving the first store forever. Export state is
        // per-store too: a sheet or failure alert generated against the old
        // store shouldn't survive the swap.
        .task(id: ObjectIdentifier(store)) {
            if model.store !== store {
                model = PeriscopeViewerModel(store: store)
                export = nil
                exportFailed = false
            }
            await model.run()
        }
    }

    /// The flat, newest-first logs list — the first tab. Owns the filter/
    /// export toolbar, search, and the export sheet.
    private var logsTab: some View {
        @Bindable var model = model
        return content
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SpanTreeView(store: store)
                    } label: {
                        Label("Span Tree", systemImage: "stopwatch")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SpanHistoryView(store: store)
                    } label: {
                        Label("Span History", systemImage: "chart.bar.xaxis")
                    }
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
            Picker("Span Exit", selection: $model.selectedSpanExitMode) {
                Text("All Events").tag(SpanExit.Mode?.none)
                ForEach(SpanExit.Mode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(SpanExit.Mode?.some(mode))
                }
            }
            Divider()
            Picker("Row Density", selection: $density) {
                ForEach(PeriscopeStylesheet.Density.allCases, id: \.self) { density in
                    Text(density.displayName).tag(density)
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

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(export.text)
                    .font(stylesheet.typography.payload)
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
