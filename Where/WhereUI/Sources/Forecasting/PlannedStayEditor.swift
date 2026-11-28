import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Creates or edits one stay without changing tracking or the other stays.
struct PlannedStayEditorDestination: View {
    private let makeModel: () -> PlannedStayEditorModel

    init(report: YearReportModel, mode: PlannedStayEditorModel.Mode) {
        self.init { PlannedStayEditorModel(report: report, mode: mode) }
    }

    init(makeModel: @escaping () -> PlannedStayEditorModel) {
        self.makeModel = makeModel
    }

    var body: some View {
        ObservableHostingView(makeModel) {
            PlannedStayEditor(model: $0)
        }
    }
}

struct PlannedStayEditor: View {
    @Bindable var model: PlannedStayEditorModel
    @State private var showsManageRegions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.report.forecasts.loadFailure {
                    PlanningLoadFailureSection(
                        message: error.localizedDescription,
                        retry: { Task { await model.report.forecasts.refresh() } },
                    )
                }

                PlannedStayDestinationSection(model: model, manage: { showsManageRegions = true })

                PlannedStayBoundarySection(
                    title: String(localized: .plannedStayEditorArrival),
                    boundary: $model.arrival,
                )
                PlannedStayBoundarySection(
                    title: String(localized: .plannedStayEditorLastDay),
                    boundary: $model.departure,
                )

                PlannedStayValidationSection(validationMessage: model.validationMessage)

                if model.hasDefiniteOverlap || model.hasPossibleOverlap {
                    PlannedStayOverlapSection(model: model)
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
                        DeletePlannedStayButton(model: model, dismiss: dismiss.callAsFunction)
                    }
                }
            }
            .environment(\.calendar, model.report.calendar)
            .environment(\.timeZone, model.report.calendar.timeZone)
            .disabled(model.isSaving)
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
                        SavePlannedStayButton(model: model, dismiss: dismiss.callAsFunction)
                    }
                }
            }
        }
        .sheet(isPresented: $showsManageRegions, onDismiss: {
            Task { await model.regionSelection.load() }
        }) {
            RegionsSettingsView(
                usedThisYear: Set(model.report.report?.totals.keys.map(\.self) ?? []),
            )
        }
        .task { await model.load() }
    }
}

private struct DeletePlannedStayButton: View {
    let model: PlannedStayEditorModel
    let dismiss: () -> Void

    var body: some View {
        Button(String(localized: .plannedStayEditorDelete), role: .destructive) {
            Task {
                if await model.delete() {
                    dismiss()
                }
            }
        }
    }
}

private struct SavePlannedStayButton: View {
    let model: PlannedStayEditorModel
    let dismiss: () -> Void

    var body: some View {
        Button(String(localized: .commonSave)) {
            Task {
                if await model.save() {
                    dismiss()
                }
            }
        }
        .disabled(!model.canSave)
    }
}

private struct PlannedStayOverlapSection: View {
    let model: PlannedStayEditorModel

    var body: some View {
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
}

private struct PlannedStayValidationSection: View {
    let validationMessage: String?

    var body: some View {
        Section {
            if let message = validationMessage {
                Label(message, systemSymbol: .exclamationmarkCircle)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(String(localized: .plannedStayEditorDatesFooter))
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
                PlannedStayEditorDestination(
                    report: PreviewSupport.loadedYearReportModel(),
                    mode: .new(initialRegion: nil),
                )
            }
            whereSnapshot(name: "AnyRegion", configurations: .fullContentPhoneLightDark) {
                PlannedStayEditorDestination(
                    report: PreviewSupport.loadedYearReportModel(),
                    mode: .new(initialRegion: PrimaryRegionDraft.supportedRegions.first {
                        $0 != .newYork && $0 != .california
                    }),
                )
            }
            whereSnapshot(
                name: "FlexibleStay",
                configurations: .fullContentScreenRepresentative,
            ) {
                let report = PreviewSupport.itineraryYearReportModel()
                PlannedStayEditor(model: flexibleEditorModel(report: report))
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
            PlannedStayEditorDestination(report: world.report, mode: .new(initialRegion: nil))
        }
    }
#endif
