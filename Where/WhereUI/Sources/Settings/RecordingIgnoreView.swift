import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Device-scoped automatic-selection controls and durable history, including elapsed choices.
struct RecordingIgnoreView: View {
    @State private var model: RecordingIgnoreModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.timeZone) private var timeZone

    init(session: WhereSession, deviceID: RecordingDeviceID, name: String) {
        _model = State(initialValue: .init(
            services: session.services,
            deviceID: deviceID,
            name: name,
            now: session.now,
        ))
    }

    init(model: RecordingIgnoreModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Text(model.name).font(.headline)
                Button(String(localized: .recordingIgnoreUntil)) { model.start(timeZone: timeZone) }
                    .disabled(model.state.history == nil)
                    .accessibilityIdentifier("where_recording_ignore_start")
            } footer: {
                Text(String(localized: .recordingIgnoreDetail))
            }
            if let history = model.state.history {
                RecordingIgnoreHistorySections(model: model, history: history)
            }
            switch model.state {
                case .idle:
                    Section { ProgressView(String(localized: .recordingIgnoreLoading)) }
                case let .loading(previous) where previous.history == nil:
                    Section { ProgressView(String(localized: .recordingIgnoreLoading)) }
                case .loading, .loaded, .retired: EmptyView()
                case let .failed(error, _):
                    Section {
                        Label(
                            WhereFormat.recordingIgnoreFailure(error),
                            systemSymbol: .exclamationmarkTriangle,
                        )
                        Button(String(localized: .commonRetry)) { Task { await model.refresh() } }
                    }
            }
        }
        .navigationTitle(String(localized: .recordingIgnoreTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) { if scenePhase == .active { await model.run() } }
        .onDisappear { model.pause() }
        .sheet(item: $model.editor) { RecordingIgnoreEditor(model: $0) }
        .alert(
            String(localized: .settingsDevicesErrorTitle),
            isPresented: $model.isShowingError,
            presenting: model.actionError,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { error in
            Text(WhereFormat.recordingIgnoreFailure(error))
        }
    }
}

private struct RecordingIgnoreHistorySections: View {
    let model: RecordingIgnoreModel
    let history: RecordingIgnoreHistory

    var body: some View {
        Section {
            if history.segments.isEmpty, history.unknownControls.isEmpty {
                Text(String(localized: .recordingIgnoreEmpty))
            }
            ForEach(history.segments, id: \.period) { segment in
                VStack(alignment: .leading) {
                    Text(WhereFormat.recordingIgnoreResolution(segment.resolution))
                        .font(.headline)
                    Text(WhereFormat.recordingPeriod(segment.period))
                        .font(.caption)
                }
                .accessibilityElement(children: .combine)
                if model.canRestoreElapsed(segment) {
                    Button(String(localized: .recordingIgnoreUndo)) {
                        model.restoreElapsed(segment.period)
                    }
                    .accessibilityLabel(String(localized: .recordingIgnoreUndoPeriod(WhereFormat
                            .recordingPeriod(segment.period))))
                    .accessibilityIdentifier("where_recording_ignore_undo")
                }
            }
        } header: {
            Text(String(localized: .recordingIgnorePeriods))
        } footer: {
            Text(String(localized: .recordingIgnorePrecedence))
        }
        if !history.unknownControls.isEmpty {
            Section {
                Label(
                    String(localized: .recordingReviewReasonUnknown),
                    systemSymbol: .exclamationmarkTriangle,
                )
            }
        }
        if !history.decisions.isEmpty {
            Section {
                ForEach(history.decisions, id: \.id) { decision in
                    RecordingIgnoreDecisionRow(model: model, decision: decision)
                }
            } header: {
                Text(String(localized: .recordingIgnoreChoices))
            } footer: {
                Text(String(localized: .recordingIgnoreChoicesDetail))
            }
        }
    }
}

private struct RecordingIgnoreDecisionRow: View {
    let model: RecordingIgnoreModel
    let decision: RecordingIgnoreDecision
    @State private var isExpanded: Bool

    init(model: RecordingIgnoreModel, decision: RecordingIgnoreDecision) {
        self.model = model
        self.decision = decision
        _isExpanded = State(initialValue: model.canResume(decision))
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(decision.periods, id: \.self) { period in
                Text(WhereFormat.recordingPeriod(period)).font(.caption)
            }
            if case let .ignore(until) = decision.change {
                Text(WhereFormat.recordingTimeZone(until.timeZone)).foregroundStyle(.secondary)
                Button(String(localized: .recordingIgnoreChangeEnd)) {
                    model.changeEnd(of: decision)
                }
                .accessibilityIdentifier("where_recording_ignore_change_end")
                if model.canResume(decision) {
                    Button(String(localized: .recordingIgnoreResume)) { model.resume(decision) }
                        .accessibilityIdentifier("where_recording_ignore_resume")
                }
            }
        } label: {
            Text(WhereFormat.recordingIgnoreDecision(decision))
                .accessibilityIdentifier("where_recording_ignore_decision")
        }
    }
}

#if DEBUG
    extension RecordingIgnoreView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingIgnorePreviewFixture.HistoryScenario.allCases {
                let fixture = RecordingIgnorePreviewFixture(history: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .history ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) { RecordingIgnorePreview(fixture: fixture) }
            }
        }
    }

    #Preview { RecordingIgnoreView.snapshotPreviews }

    extension RecordingIgnoreView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingIgnoreView.self,
            title: "Device ignore history",
            navigationContainer: .none,
            routes: [.push(to: RecordingIgnoreEditor.flyoverID)],
        )
    }
#endif
