import PeriscopeCore
import SwiftUI

/// The log viewer: two surfaces switched by a nav-bar segmented control — a
/// reverse-chronological, searchable **Logs** list over a `PeriscopeStore`
/// (filterable by level, event type, scope subtree, session, and span exit,
/// with NDJSON export) and the scope **Hierarchy** browser.
///
/// Designed to be pushed inside an existing `NavigationStack` (it sets a
/// navigation title and toolbar but does not create its own stack — so a
/// single stack owns the bar and every drill-in, rather than a nested
/// `TabView` whose per-tab toolbar wouldn't reliably reach the host bar). A
/// developer surface — gate it behind `#if DEBUG` or a developer menu.
public struct PeriscopeViewer: View {
    private let store: PeriscopeStore
    private let title: String
    private let defaults: UserDefaults
    @State private var model: PeriscopeViewerModel
    @State private var export: NDJSONExport?
    @State private var exportFailed = false
    @State private var density: PeriscopeStylesheet.Density
    @State private var mode: Mode = .logs
    @State private var spanDestination: SpanDestination?

    /// The viewer's two surfaces, switched by the nav-bar segmented control.
    /// A single stack-hosted view (rather than a `TabView`) so the toolbar
    /// reliably hosts on the pushing stack's bar — matching the sibling
    /// developer tools — and every push lands on that one stack (no
    /// cross-surface toolbar/back-stack bleed).
    private enum Mode: Hashable, CaseIterable {
        case logs
        case hierarchy

        var label: String {
            switch self {
                case .logs: "Logs"
                case .hierarchy: "Hierarchy"
            }
        }
    }

    /// The span surfaces reachable from the Logs toolbar's Spans menu, pushed
    /// onto the host stack via `navigationDestination` (a menu keeps the bar
    /// uncrowded and both surfaces discoverable).
    private enum SpanDestination: Hashable, Identifiable {
        case tree
        case history

        var id: Self {
            self
        }
    }

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
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(item: $spanDestination) { destination in
                switch destination {
                    case .tree:
                        SpanTreeView(store: store)
                    case .history:
                        SpanHistoryView(store: store)
                }
            }
            .sheet(item: $export) { export in
                NDJSONExportSheet(export: export)
            }
            .alert("Export Failed", isPresented: $exportFailed) {
                Button("OK", role: .cancel) {}
            }
            .environment(\.logRowDensity, density)
            .onChange(of: density) { _, newValue in
                newValue.save(to: defaults)
            }
            .periscopeBroadwayRoot()
            // Keyed on the store's identity: swapping stores in place cancels
            // the old model's live stream and rebinds a fresh model —
            // `State(initialValue:)` alone would keep serving the first store
            // forever. Export/navigation/mode state is per-store too: nothing
            // generated against the old store should survive the swap.
            .task(id: ObjectIdentifier(store)) {
                if model.store !== store {
                    model = PeriscopeViewerModel(store: store)
                    export = nil
                    exportFailed = false
                    spanDestination = nil
                    mode = .logs
                }
                await model.run()
            }
    }

    /// The nav-bar segmented control that switches surfaces, plus the
    /// logs-only filter / spans / export actions (dropped on the hierarchy
    /// surface, where they don't apply).
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        if mode == .logs {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                spansMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                exportButton
            }
        }
    }

    /// The selected surface: the searchable logs list, or the scope hierarchy.
    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        switch mode {
            case .logs:
                logsList
                    .searchable(text: $model.searchText)
            case .hierarchy:
                LogHierarchyView(store: store)
        }
    }

    /// The flat, newest-first logs list — loading / failed / empty / loaded.
    @ViewBuilder
    private var logsList: some View {
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
                    Text(session.displayLabel).tag(UUID?.some(session.id))
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

    /// The Spans menu: the store's span surfaces, grouped so the bar stays
    /// uncrowded. Selecting one pushes it via `spanDestination`.
    private var spansMenu: some View {
        Menu {
            Button {
                spanDestination = .tree
            } label: {
                Label("Span Tree", systemImage: "stopwatch")
            }
            Button {
                spanDestination = .history
            } label: {
                Label("Span History", systemImage: "chart.bar.xaxis")
            }
        } label: {
            Label("Spans", systemImage: "stopwatch")
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
