import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Exact place-evidence review; saving does not infer observations or select a recording device.
struct RecordingPlaceEditor: View {
    let model: RecordingPlaceEditorModel
    @State private var locationPicker: RecordingPlaceLocationModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch model.draft {
                        case let .definition(definition):
                            RecordingPlaceDefinitionFields(definition: definition) {
                                locationPicker = .init(coordinate: definition.coordinate)
                            }
                        case .remove:
                            Text(String(localized: .recordingPlaceRemoveDetail))
                    }
                    RecordingPlaceBoundsFields(bounds: model.bounds)
                } footer: {
                    Text(String(localized: .recordingPlaceBoundsDetail))
                }
                .disabled(model.controls.isBusy || model.controls.didApply)
                RecordingControlStatus(
                    model: model.controls,
                    context: .place,
                    canRetry: model.canRetry,
                    retry: { Task { await model.retry() } },
                )
                if let inspection = model.inspection {
                    switch inspection {
                        case let .success(inspection):
                            Section {
                                ForEach(inspection.changes, id: \.period) { change in
                                    VStack(alignment: .leading) {
                                        Text(WhereFormat.recordingInterval(change.period))
                                            .font(.headline)
                                        Text(String(localized: .recordingPlaceBefore(WhereFormat
                                                .recordingPlaceDefinition(change.before))))
                                        Text(String(localized: .recordingPlaceAfter(WhereFormat
                                                .recordingPlaceDefinition(change.after))))
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            } header: {
                                Text(String(localized: .recordingPlacePreview))
                            } footer: {
                                Text(String(localized: .recordingPlaceDetail))
                            }
                            RecordingPlaceUnknownControls(records: inspection.unknownControls)
                        case let .failure(error):
                            Section { Text(WhereFormat.recordingPlaceFailure(error)) }
                    }
                }
                if !model.controls.didApply {
                    Section {
                        switch model.edits {
                            case .success:
                                if model.canApply {
                                    Button(String(localized: .recordingPlaceSave)) {
                                        Task { await model.apply() }
                                    }
                                    .accessibilityIdentifier("where_recording_place_apply")
                                } else if !model.canRetry {
                                    Button(String(localized: .recordingPlaceReview)) {
                                        Task { await model.review() }
                                    }
                                    .accessibilityIdentifier("where_recording_place_review")
                                }
                            case let .failure(error):
                                Text(WhereFormat.recordingPlaceFailure(error))
                        }
                    } footer: {
                        Text(String(localized: .recordingReviewSaveDetail))
                    }
                    .disabled(model.controls.isBusy)
                }
            }
            .environment(\.calendar, RecordingScopeEditorModel.pickerCalendar)
            .environment(\.timeZone, .gmt)
            .navigationTitle(String(localized: .recordingPlaceTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .commonDone)) { dismiss() }
                        .accessibilityIdentifier("where_recording_place_close")
                }
            }
            .sheet(item: $locationPicker) { picker in
                RecordingPlaceLocationPicker(model: picker) { coordinate in
                    if case let .definition(definition) = model.draft {
                        definition.coordinate = coordinate
                    }
                }
            }
        }
    }
}

private struct RecordingPlaceDefinitionFields: View {
    @Bindable var definition: RecordingPlaceEditorModel.Definition
    let choose: () -> Void
    var body: some View {
        Picker(String(localized: .recordingPlaceKind), selection: $definition.kind) {
            Text(String(localized: .recordingPlaceHome)).tag(RecordingPlace.Kind.regularHome)
            Text(String(localized: .recordingPlaceBase)).tag(RecordingPlace.Kind.temporaryBase)
        }
        .pickerStyle(.inline)
        if let coordinate = definition.coordinate {
            Text(WhereFormat.auditCoordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
            ))
        }
        Button(String(localized: .recordingPlaceChoose), action: choose)
            .accessibilityIdentifier("where_recording_place_choose_location")
    }
}

private struct RecordingPlaceBoundsFields: View {
    @Bindable var bounds: RecordingPlaceEditorModel.Bounds
    var body: some View {
        WhereDatePicker(
            String(localized: .recordingPlaceValidFrom),
            selection: $bounds.start,
            displayedComponents: [.date, .hourAndMinute],
        )
        .accessibilityIdentifier("where_recording_place_start")
        Toggle(String(localized: .recordingPlaceHasEnd), isOn: $bounds.hasEnd)
            .accessibilityIdentifier("where_recording_place_has_end")
        if bounds.hasEnd {
            WhereDatePicker(
                String(localized: .recordingPlaceValidEnd),
                selection: $bounds.endDate,
                displayedComponents: [.date, .hourAndMinute],
            )
            .accessibilityIdentifier("where_recording_place_end")
        }
    }
}

/// Opaque scopes remain visible in both history and exact proposal inspection.
struct RecordingPlaceUnknownControls: View {
    let records: [VersionedHistoryRecord]
    var body: some View {
        if !records.isEmpty {
            Section {
                Label(
                    String(localized: .recordingPlaceUnknown),
                    systemSymbol: .exclamationmarkTriangle,
                )
                ForEach(records, id: \.id) { record in
                    Text(WhereFormat.recordingControlScope(record.scope)).font(.caption)
                }
            }
        }
    }
}

#if DEBUG
    extension RecordingPlaceEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingPlacePreviewFixture.EditorScenario.allCases {
                let fixture = RecordingPlacePreviewFixture(editor: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .reviewed ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: fixture.prepare,
                ) {
                    RecordingPlacePreview(fixture: fixture)
                }
            }
        }
    }

    #Preview { RecordingPlaceEditor.snapshotPreviews }
    extension RecordingPlaceEditor: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            RecordingPlaceEditor.self,
            title: "Review place changes",
            navigationContainer: .none,
            routes: [.modal(to: RecordingPlaceLocationPicker.flyoverID)],
        )
    }
#endif
