import SwiftUI
import WhereCore

/// App root. Shows the selected year's region-presence report with a
/// year stepper in the navigation bar.
public struct RootView: View {
    @State private var model: WhereModel

    /// App entry point. The production controller is built lazily on
    /// first load, so this initializer stays cheap and synchronous.
    public init() {
        _model = State(initialValue: WhereModel())
    }

    /// Inject a controller (tests / previews) wired to an in-memory
    /// store and a `ScriptedLocationSource`.
    public init(controller: WhereController) {
        _model = State(initialValue: WhereModel(controller: controller))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Where")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { yearSelector }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
            case .loading:
                ProgressView()
                    .accessibilityIdentifier("where_loading")
            case let .failed(message):
                ContentUnavailableView {
                    Label("Couldn’t load report", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") { Task { await model.load() } }
                }
            case let .loaded(report):
                YearReportView(report: report)
        }
    }

    private var yearSelector: some View {
        HStack(spacing: 16) {
            Button {
                Task { await model.selectYear(model.year - 1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous year")

            Text(verbatim: String(model.year))
                .font(.headline)
                .monospacedDigit()
                .accessibilityIdentifier("where_root_title")

            Button {
                Task { await model.selectYear(model.year + 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next year")
        }
    }
}

#Preview("Populated") {
    SeededPreview { controller in
        let calendar = Calendar(identifier: .gregorian)
        func day(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2025, month: month, day: day)) ?? .now
        }
        try? await controller.addManualDay(date: day(1, 3), regions: [.california])
        try? await controller.addManualDay(date: day(2, 14), regions: [.california, .newYork])
        try? await controller.addManualDay(date: day(6, 1), regions: [.newYork])
        try? await controller.addManualDay(date: day(8, 20), regions: [.europeanUnion])
        try? await controller.addManualDay(date: day(11, 9), regions: [.canada, .other])
    }
}

#Preview("Empty") {
    SeededPreview { _ in }
}

/// Builds an in-memory controller, runs `seed`, then shows `RootView`.
/// Keeps the async setup out of the `#Preview` body.
private struct SeededPreview: View {
    let seed: (WhereController) async -> Void

    @State private var controller: WhereController?

    var body: some View {
        Group {
            if let controller {
                RootView(controller: controller)
            } else {
                ProgressView()
            }
        }
        .task {
            guard controller == nil else { return }
            guard let store = try? SwiftDataStore.inMemory() else { return }
            let made = WhereController(store: store, locationSource: ScriptedLocationSource())
            await seed(made)
            controller = made
        }
    }
}
