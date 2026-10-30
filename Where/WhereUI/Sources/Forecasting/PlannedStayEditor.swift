import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Creates or edits one stay without changing tracking or the other stays.
struct PlannedStayEditor: View {
    @State private var model: PlannedStayEditorModel
    @State private var showsManageRegions = false
    @Environment(\.dismiss) private var dismiss

    init(
        report: YearReportModel,
        stay: PlannedStay? = nil,
        initialRegion: Region? = nil,
    ) {
        _model = State(initialValue: PlannedStayEditorModel(
            report: report,
            mode: stay.map(PlannedStayEditorModel.Mode.edit) ?? .new(initialRegion: initialRegion),
        ))
    }

    init(model: PlannedStayEditorModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Group {
                    if let error = model.report.forecasts.loadFailure {
                        Section {
                            Label(
                                error.localizedDescription,
                                systemSymbol: .exclamationmarkTriangleFill,
                            )
                            .foregroundStyle(.red)
                            Button(String(localized: .commonRetry)) {
                                Task { await model.report.forecasts.refresh() }
                            }
                        }
                    }
                    destinationSection
                    PlannedStayBoundarySection(
                        title: String(localized: .plannedStayEditorArrival),
                        boundary: $model.arrival,
                    )
                    PlannedStayBoundarySection(
                        title: String(localized: .plannedStayEditorLastDay),
                        boundary: $model.departure,
                    )
                    Section {
                        if let message = model.validationMessage {
                            Label(message, systemSymbol: .exclamationmarkCircle)
                                .foregroundStyle(.whereSecondary)
                        }
                    } footer: {
                        Text(String(localized: .plannedStayEditorDatesFooter))
                    }
                    if model.hasDefiniteOverlap || model.hasPossibleOverlap {
                        Section {
                            if model.hasDefiniteOverlap {
                                Label(
                                    String(localized: .plannedStaysDefiniteOverlap),
                                    systemSymbol: .rectangleOnRectangle,
                                )
                            }
                            if model.hasPossibleOverlap {
                                Label(
                                    String(localized: .plannedStaysPossibleOverlap),
                                    systemSymbol: .rectangleDashed,
                                )
                            }
                        } footer: {
                            Text(String(localized: .plannedStaysOverlapFooter))
                        }
                    }
                    if case let .failed(error) = model.saveState {
                        Section {
                            Label(
                                error.localizedDescription,
                                systemSymbol: .exclamationmarkTriangleFill,
                            )
                            .foregroundStyle(.red)
                        }
                    }
                    if model.isEditing {
                        Section {
                            Button(
                                String(localized: .plannedStayEditorDelete),
                                role: .destructive,
                            ) {
                                Task {
                                    if await model.delete() { dismiss() }
                                }
                            }
                        }
                    }
                }.whereThemeListRow()
            }
            .environment(\.calendar, model.report.calendar)
            .environment(\.timeZone, model.report.calendar.timeZone)
            .disabled(model.isSaving)
            .whereThemeScreen(.sheet)
            .navigationTitle(String(localized: model.isEditing
                    ? .plannedStayEditorEditTitle
                    : .plannedStayEditorNewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel), action: dismiss.callAsFunction)
                        .disabled(model.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.isSaving {
                        ProgressView()
                            .accessibilityLabel(String(localized: .commonSave))
                    } else {
                        Button(String(localized: .commonSave)) {
                            Task {
                                if await model.save() { dismiss() }
                            }
                        }
                        .disabled(!model.canSave)
                    }
                }
            }
        }
        .whereThemeActivity(!showsManageRegions)
        .sheet(isPresented: $showsManageRegions, onDismiss: {
            Task { await model.regionSelection.load() }
        }) {
            RegionsSettingsView(
                usedThisYear: Set(model.report.report?.totals.keys.map(\.self) ?? []),
            )
        }
        .task { await model.load() }
    }

    private var destinationSection: some View {
        Section {
            NavigationLink {
                PlanningRegionPickerView(
                    model: model.regionSelection,
                    title: String(localized: .plannedStayEditorDestination),
                    selectedRegion: model.region,
                ) { region in
                    model.region = region
                }
            } label: {
                LabeledContent(String(localized: .plannedStayEditorDestination)) {
                    Text(model.region?
                        .localizedName ?? String(localized: .plannedStayEditorChooseRegion))
                }
            }
            if let region = model.region,
               let tracked = model.regionSelection.trackedRegions,
               !tracked.contains(region)
            {
                Text(String(localized: .plannedStayEditorUntracked))
                    .foregroundStyle(.whereSecondary)
                Button(String(localized: .settingsRegionsManage), systemSymbol: .map) {
                    showsManageRegions = true
                }
            }
            if case let .failed(error) = model.regionSelection.loadState {
                Label(error.localizedDescription, systemSymbol: .exclamationmarkTriangle)
                    .foregroundStyle(.whereSecondary)
                Button(String(localized: .commonRetry)) {
                    Task { await model.regionSelection.load() }
                }
            }
        } footer: {
            Text(String(localized: .plannedStayEditorDestinationFooter))
        }
    }
}

#if DEBUG
    extension PlannedStayEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "NewStay",
                configurations: .fullContentScreenRepresentative,
            ) {
                PlannedStayEditor(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "AnyRegion", configurations: .fullContentPhoneLightDark) {
                PlannedStayEditor(
                    report: PreviewSupport.loadedYearReportModel(),
                    initialRegion: PrimaryRegionSelectionModel.usRegions.first {
                        $0 != .newYork && $0 != .california
                    },
                )
            }
            whereSnapshot(
                name: "FlexibleStay",
                configurations: .fullContentScreenRepresentative,
            ) {
                let report = PreviewSupport.itineraryYearReportModel()
                PlannedStayEditor(report: report, stay: report.forecasts.planning.stays.first {
                    !$0.arrival.isExact || !$0.departure.isExact
                })
            }
            whereSnapshot(name: "DefiniteOverlap", configurations: .fullContentPhoneLightDark) {
                PlannedStayEditor(model: definiteOverlapEditorModel())
            }
            let staleModel = flexibleEditorModel(report: PreviewSupport.itineraryYearReportModel())
            whereSnapshot(
                name: "DeletedWhileEditing",
                configurations: .fullContentPhoneLightDarkWithAnnotations,
                onReadyToMeasure: {
                    // The preview mirrors an itinerary over an empty store.
                    // Await the real rejection before measuring its error row.
                    let saved = await staleModel.save()
                    precondition(!saved, "The stale editor fixture must expose the save failure")
                },
            ) {
                PlannedStayEditor(model: staleModel)
            }
        }

        private static func definiteOverlapEditorModel() -> PlannedStayEditorModel {
            let report = PreviewSupport.itineraryYearReportModel()
            let model = flexibleEditorModel(report: report)
            guard let other = report.forecasts.planning.stays
                .first(where: { $0.region == .california })
            else {
                preconditionFailure(
                    "The itinerary fixture requires the overlapping California stay",
                )
            }
            model.departure.earliest = other.arrival.earliest.startOfDay(in: report.calendar)
            return model
        }

        private static func flexibleEditorModel(report: YearReportModel) -> PlannedStayEditorModel {
            guard let stay = report.forecasts.planning.stays.first(where: {
                !$0.arrival.isExact || !$0.departure.isExact
            }) else {
                preconditionFailure("The itinerary fixture requires a flexible stay")
            }
            return PlannedStayEditorModel(report: report, mode: .edit(stay))
        }
    }

    #Preview { PlannedStayEditor.snapshotPreviews }

    extension PlannedStayEditor: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            PlannedStayEditor.self,
            title: "Planned Stay Editor",
            navigationContainer: .none,
        ) { world in
            PlannedStayEditor(report: world.report)
        }
    }
#endif
