import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Independently editable itinerary and the policy for unplanned future days.
struct PlannedStaysView: View {
    @State private var model: PlannedStaysModel
    @Environment(\.dismiss) private var dismiss

    init(report: YearReportModel, initialRegion: Region? = nil) {
        self.init(model: PlannedStaysModel(
            report: report,
            initialRegion: initialRegion,
        ))
    }

    init(model: PlannedStaysModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                if let error = model.report.forecasts.loadFailure {
                    PlanningLoadFailureSection(
                        message: error.localizedDescription,
                        retry: { Task { await model.report.forecasts.refresh() } },
                    )
                }

                UpcomingStaysSection(model: model)

                if model.report.forecasts.hasLoaded {
                    UnplannedDaysSection(model: model)
                }

                if !model.past.isEmpty {
                    PastStaysSection(model: model)
                }
            }
            .navigationTitle(String(localized: .plannedStaysTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: .commonDone), action: dismiss.callAsFunction)
                }
            }
        }
        .sheet(item: $model.editorRoute) { route in
            PlannedStayEditorDestination(report: model.report, mode: route.mode)
        }
        .task { await model.load() }
    }
}

private struct UpcomingStaysSection: View {
    let model: PlannedStaysModel

    var body: some View {
        Section {
            if !model.report.forecasts.hasLoaded,
               model.report.forecasts.loadFailure == nil
            {
                ProgressView()
            } else if model.report.forecasts.hasLoaded, model.upcoming.isEmpty {
                Text(String(localized: .plannedStaysEmpty))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.upcoming) { stay in
                    EditPlannedStayButton(stay: stay, model: model)
                }
            }
            AddPlannedStayButton(add: model.add)
        } header: {
            Text(String(localized: .plannedStaysUpcoming))
        } footer: {
            Text(String(localized: .plannedStaysFooter))
        }
    }
}

private struct PastStaysSection: View {
    @Bindable var model: PlannedStaysModel

    var body: some View {
        Section {
            DisclosureGroup(
                String(localized: .plannedStaysPast),
                isExpanded: $model.showsPast,
            ) {
                ForEach(model.past) { stay in
                    EditPlannedStayButton(stay: stay, model: model)
                }
            }
        } footer: {
            Text(String(localized: .plannedStaysPastFooter))
        }
    }
}

private struct UnplannedDaysSection: View {
    let model: PlannedStaysModel

    var body: some View {
        Section {
            PastTravelPatternButton(model: model)
            PlanningHomeRegionLink(report: model.report)
            if case let .failed(error) = model.saveState {
                Label(error.localizedDescription, systemSymbol: .exclamationmarkTriangleFill)
                    .foregroundStyle(.red)
            }
        } header: {
            Text(String(localized: .plannedStaysUnplannedDays))
        } footer: {
            Text(String(localized: model.report.forecasts.planning.homeRegion == nil
                    ? .plannedStaysPastPatternFooter
                    : .plannedStaysHomeRegionFooter))
        }
        .disabled(model.isSaving)
    }
}

private struct AddPlannedStayButton: View {
    let add: () -> Void

    var body: some View {
        Button(
            String(localized: .plannedStaysAdd),
            systemSymbol: .plus,
            action: add,
        )
    }
}

private struct EditPlannedStayButton: View {
    let stay: PlannedStay
    let model: PlannedStaysModel

    var body: some View {
        Button {
            model.edit(stay)
        } label: {
            PlannedStaySummaryRow(
                stay: stay,
                calendar: model.report.calendar,
                hasDefiniteOverlap: model.usesDefiniteOverlap(stay),
                hasPossibleOverlap: model.usesPossibleOverlap(stay),
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: .plannedStaysEditHint))
    }
}

private struct PastTravelPatternButton: View {
    let model: PlannedStaysModel

    var body: some View {
        Button {
            Task { await model.usePastTravelPattern() }
        } label: {
            HStack {
                Label(
                    String(localized: .plannedStaysPastPattern),
                    systemSymbol: .clockArrowTriangleheadCounterclockwiseRotate90,
                )
                .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if model.report.forecasts.planning.homeRegion == nil {
                    Image(systemSymbol: .checkmark)
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(model.report.forecasts.planning
            .homeRegion == nil ? [.isSelected] : [])
    }
}

private struct PlanningHomeRegionLink: View {
    let report: YearReportModel

    var body: some View {
        NavigationLink {
            HomeRegionPickerDestination(report: report)
        } label: {
            LabeledContent {
                HStack {
                    Text(report.forecasts.planning.homeRegion?.localizedName
                        ?? String(localized: .plannedStayEditorChooseRegion))
                    if report.forecasts.planning.homeRegion != nil {
                        Image(systemSymbol: .checkmark).foregroundStyle(.tint)
                    }
                }
            } label: {
                Label(String(localized: .plannedStaysHomeRegion), systemSymbol: .house)
            }
        }
        .accessibilityAddTraits(report.forecasts.planning
            .homeRegion != nil ? [.isSelected] : [])
    }
}

private struct HomeRegionPickerDestination: View {
    let report: YearReportModel

    var body: some View {
        ObservableHostingView {
            PlanningRegionSelectionModel(report: report)
        } content: { model in
            PlanningRegionPickerView(
                model: model,
                title: String(localized: .plannedStaysHomeRegion),
                selectedRegion: report.forecasts.planning.homeRegion,
            ) { region in
                try await report.forecasts.setHomeRegion(region)
            }
        }
    }
}

#if DEBUG
    extension PlannedStaysView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Empty", configurations: .fullContentPhoneLightDark) {
                PlannedStaysView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "Itinerary", configurations: .fullContentScreenRepresentative) {
                PlannedStaysView(report: PreviewSupport.itineraryYearReportModel())
            }
            whereSnapshot(name: "PastTravelPattern", configurations: .fullContentPhoneLightDark) {
                PlannedStaysView(report: PreviewSupport.itineraryYearReportModel(homeRegion: nil))
            }
            whereSnapshot(
                name: "PastExpanded",
                configurations: .fullContentPhoneLightDarkWithAnnotations,
            ) {
                PlannedStaysView(model: expandedPastModel())
            }
        }
    }

    extension PlannedStaysView {
        fileprivate static func expandedPastModel() -> PlannedStaysModel {
            let model = PlannedStaysModel(
                report: PreviewSupport.itineraryYearReportModel(),
                initialRegion: nil,
            )
            model.showsPast = true
            return model
        }
    }

    #Preview { PlannedStaysView.snapshotPreviews }

    extension PlannedStaysView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            PlannedStaysView.self,
            title: "Planned Stays",
            navigationContainer: .none,
            routes: [.modal(to: PlannedStayEditor.flyoverID)],
        ) { world in
            PlannedStaysView(report: world.report)
        }
    }
#endif
