import BroadwayCore
import PeriscopeCore
import SFSafeSymbols
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
    fileprivate enum Mode: Hashable, CaseIterable {
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
    fileprivate enum SpanDestination: Hashable, Identifiable {
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
        LogViewerContent(model: model, store: store, mode: mode)
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
            LogViewerModePicker(mode: $mode)
        }
        if mode == .logs {
            ToolbarItem(placement: .primaryAction) {
                LogFilterMenu(model: model, density: $density)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SpanNavigationMenu(destination: $spanDestination)
            }
            ToolbarItem(placement: .topBarTrailing) {
                LogExportButton(export: exportNDJSON)
            }
        }
    }

    private func exportNDJSON() async {
        do {
            export = try await NDJSONExport(text: model.exportNDJSON())
        } catch {
            PeriscopeToolsLog.failures.error(
                "NDJSON export could not read the store: \(error, privacy: .public)",
            )
            exportFailed = true
        }
    }
}

private struct LogViewerContent: View {
    @Bindable var model: PeriscopeViewerModel
    let store: PeriscopeStore
    let mode: PeriscopeViewer.Mode

    var body: some View {
        switch mode {
            case .logs:
                LogViewerList(model: model, store: store)
                    .searchable(text: $model.searchText)
            case .hierarchy:
                LogHierarchyView(store: store)
        }
    }
}

private struct LogViewerModePicker: View {
    @Binding var mode: PeriscopeViewer.Mode

    var body: some View {
        Picker("View", selection: $mode) {
            ForEach(PeriscopeViewer.Mode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }
}

private struct SpanNavigationMenu: View {
    @Binding var destination: PeriscopeViewer.SpanDestination?

    var body: some View {
        Menu {
            SpanNavigationButton(destination: .tree) { destination = .tree }
            SpanNavigationButton(destination: .history) { destination = .history }
        } label: {
            Label("Spans", systemSymbol: .stopwatch)
        }
    }
}

private struct SpanNavigationButton: View {
    let destination: PeriscopeViewer.SpanDestination
    let navigate: () -> Void

    var body: some View {
        Button(action: navigate) {
            switch destination {
                case .tree: Label("Span Tree", systemSymbol: .stopwatch)
                case .history: Label("Span History", systemSymbol: .chartBarXaxis)
            }
        }
    }
}

private struct LogExportButton: View {
    let export: () async -> Void

    var body: some View {
        Button {
            Task { await export() }
        } label: {
            Label("Export", systemSymbol: .squareAndArrowUp)
        }
    }
}

/// A generated NDJSON export, presented in a share sheet.
struct NDJSONExport: Identifiable {
    let id = PresentationID<NDJSONExport>()
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

private struct LogViewerList: View {
    let model: PeriscopeViewerModel
    let store: PeriscopeStore

    var body: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(reason):
                ContentUnavailableView(
                    "Logs Unavailable",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(reason),
                )
            case let .loaded(events) where events.isEmpty:
                ContentUnavailableView(
                    "No Logs",
                    systemSymbol: .docTextMagnifyingglass,
                    description: Text("No stored events match the current filters."),
                )
            case let .loaded(events):
                LogViewerEvents(events: events, model: model, store: store)
        }
    }
}

private struct LogViewerEvents: View {
    let events: [StoredLogEvent]
    let model: PeriscopeViewerModel
    let store: PeriscopeStore

    var body: some View {
        List {
            ForEach(events) { event in
                LogEventLink(event: event, scopePath: model.scopePath(for: event), store: store)
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

#if DEBUG
    #Preview {
        PeriscopeToolsPreview { fixture in
            PeriscopeViewer(store: fixture.store)
        }
    }
#endif
