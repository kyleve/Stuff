import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// One source decision, shared by direct inspection and guided review. The proposal remains
/// visible after a stale save, and changing its scope requires another inspected proposal.
/// The presenting owner retires the injected model when its review page or session ends.
struct RecordingChoiceView: View {
    enum Completion { case save, saveAndContinue }

    @State private var model: RecordingChoiceModel
    @State private var scopeEditor: RecordingScopeEditorModel?
    let completion: Completion

    init(model: RecordingChoiceModel, completion: Completion) {
        _model = State(initialValue: model)
        self.completion = completion
    }

    var body: some View {
        Form {
            status
            if let presentation = model.presentation {
                scope(presentation)
                switch presentation.result {
                    case let .comparison(comparison):
                        sourceActions(comparison)
                        RecordingChoiceDetails(
                            comparison: comparison,
                            mode: model.selectedAction == nil ? .inspection : .proposal,
                        )
                    case let .needsCalendarContext(periods):
                        Section {
                            Label(
                                String(localized: .recordingReviewCalendarRequired),
                                systemSymbol: .calendarBadgeExclamationmark,
                            )
                            ForEach(periods, id: \.self) { period in
                                Text(WhereFormat.recordingPeriod(period)).font(.caption)
                            }
                            Button(String(localized: .recordingReviewOriginalPeriods)) {
                                Task { await model.useOriginalPeriods() }
                            }
                            .disabled(model.isBusy)
                        }
                    case .absentRecordingDay:
                        Section {
                            Text(String(localized: .recordingReviewAbsentDay))
                            Button(String(localized: .recordingReviewOriginalPeriods)) {
                                Task { await model.useOriginalPeriods() }
                            }
                            .disabled(model.isBusy)
                        }
                }
                if !model.didApply {
                    Section {
                        Button(String(localized: .recordingCalendarTitle)) {
                            model.openCalendarRecovery()
                        }
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("where_recording_calendar")
                    } footer: {
                        Text(String(localized: .recordingCalendarEntryDetail))
                    }
                }
                if !model.didApply {
                    Section {
                        Button(String(localized: .recordingPlaceTitle)) { model.openPlaces() }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("where_recording_places")
                    } footer: { Text(String(localized: .recordingPlaceDetail)) }
                }
                if model.selectedAction != nil, !model.didApply {
                    Section {
                        Button(String(localized: completion == .save ? .recordingReviewSave :
                                .recordingReviewSaveAndContinue))
                        {
                            Task { await model.apply() }
                        }
                        .disabled(!model.canApply)
                        .accessibilityIdentifier("where_recording_apply")
                    } footer: {
                        Text(String(localized: .recordingReviewSaveDetail))
                    }
                }
            }
        }
        .navigationTitle(String(localized: .recordingReviewTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.editor?.id) {
            if model.editor == nil { await model.loadIfNeeded() }
        }
        .sheet(item: $scopeEditor) { editor in
            RecordingScopeEditor(model: editor) { request in
                Task { await model.review(request) }
            }
        }
        .sheet(item: $model.editor) { editor in
            switch editor {
                case let .calendar(model): RecordingCalendarEditor(model: model)
                case let .places(model):
                    NavigationStack {
                        RecordingPlaceView(model: model)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(String(localized: .commonDone)) {
                                        self.model.editor = nil
                                    }
                                    .accessibilityIdentifier("where_recording_places_close")
                                }
                            }
                    }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
            case .idle, .awaitingControlRefresh, .loading:
                Section { ProgressView(String(localized: .recordingReviewLoading)) }
            case let .ready(.reviewed(_, _, refreshed)) where refreshed:
                Section {
                    Label(
                        String(localized: .recordingReviewRefreshed),
                        systemSymbol: .arrowClockwise,
                    )
                    .accessibilityIdentifier("where_recording_refreshed")
                }
            case .ready:
                EmptyView()
            case .saving:
                Section { SavingStatusRow(text: String(localized: .manualSavingStatus)) }
            case .applied:
                Section { Label(
                    String(localized: .recordingReviewSaved),
                    systemSymbol: .checkmarkCircle,
                ) }
            case let .failed(_, recovery):
                Section {
                    Label(
                        WhereFormat.recordingReviewFailure(recovery),
                        systemSymbol: .exclamationmarkTriangle,
                    )
                    Button(String(localized: .commonRetry)) { Task { await model.retry() } }
                        .accessibilityIdentifier("where_recording_retry")
                }
        }
    }

    private func scope(_ presentation: RecordingChoicePresentation) -> some View {
        Section {
            switch presentation.request.scope {
                case .periods:
                    ForEach(presentation.periods, id: \.self) { period in
                        Text(WhereFormat.recordingPeriod(period))
                    }
                case let .recordingDay(deviceID, day):
                    LabeledContent(WhereFormat.calendarDay(
                        day,
                        format: .dateTime.month(.abbreviated).day().year(),
                    )) {
                        Text(WhereFormat.recordingDevice(deviceID, names: presentation.names))
                    }
                    ForEach(presentation.periods, id: \.self) { period in
                        Text(WhereFormat.recordingPeriod(period)).font(.caption)
                    }
            }
            if let action = model.selectedAction {
                Text(WhereFormat.recordingAction(action, names: presentation.names))
                Button(String(localized: .recordingScopeTitle)) {
                    scopeEditor = RecordingScopeEditorModel(
                        presentation: presentation,
                        originalPeriods: model.originalPeriods,
                    )
                }
                .disabled(model.isBusy || model.didApply)
                .accessibilityIdentifier("where_recording_edit_scope")
            }
        } header: {
            Text(String(localized: .recordingReviewScope))
        }
    }

    private func sourceActions(_ comparison: RecordingChoicePresentation.Comparison) -> some View {
        Section {
            ForEach(comparison.tracks) { track in
                Button(String(localized: .recordingReviewUseDevice(track.name))) {
                    Task { await model.choose(.select(track.id)) }
                }
                .accessibilityIdentifier("where_recording_choose_\(track.id.rawValue.uuidString)")
            }
            Button(String(localized: .recordingReviewAutomatic)) {
                Task { await model.choose(.automatic) }
            }
            .accessibilityIdentifier("where_recording_automatic")
        } header: {
            Text(String(localized: .recordingReviewChooseSource))
        } footer: {
            Text(String(localized: .recordingReviewExclusiveDetail))
        }
        .disabled(model.isBusy || model.didApply)
    }
}

#if DEBUG
    extension RecordingChoiceView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingReviewPreviewFixture.Scenario.allCases {
                let fixture = RecordingReviewPreviewFixture(scenario: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .browsing ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) {
                    RecordingReviewPreview(fixture: fixture) { fixture in
                        if let state = fixture.preparedState {
                            NavigationStack {
                                RecordingChoiceView(model: state.choice, completion: .save)
                                    .id(ObjectIdentifier(state.choice))
                            }
                        }
                    }
                }
            }
        }
    }

    #Preview { RecordingChoiceView.snapshotPreviews }

    extension RecordingChoiceView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingChoiceView.self,
            title: "Recording review",
            routes: [
                .modal(to: RecordingScopeEditor.flyoverID),
                .modal(to: RecordingCalendarEditor.flyoverID),
                .modal(to: RecordingPlaceView.flyoverID),
            ],
        )
    }
#endif
