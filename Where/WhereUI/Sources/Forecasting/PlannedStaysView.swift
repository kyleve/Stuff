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
                if let message = model.report.forecasts.loadFailure {
                    Section {
                        Label(message, systemSymbol: .exclamationmarkTriangleFill)
                            .foregroundStyle(.red)
                        Button(String(localized: .commonRetry)) {
                            Task { await model.report.forecasts.refresh() }
                        }
                    }
                }

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
                            stayRow(stay)
                        }
                    }
                    Button(
                        String(localized: .plannedStaysAdd),
                        systemSymbol: .plus,
                        action: model.add,
                    )
                } header: {
                    Text(String(localized: .plannedStaysUpcoming))
                } footer: {
                    Text(String(localized: .plannedStaysFooter))
                }

                if model.report.forecasts.hasLoaded {
                    gapSection
                }

                if !model.past.isEmpty {
                    Section {
                        DisclosureGroup(
                            String(localized: .plannedStaysPast),
                            isExpanded: $model.showsPast,
                        ) {
                            ForEach(model.past) { stay in
                                stayRow(stay)
                            }
                        }
                    } footer: {
                        Text(String(localized: .plannedStaysPastFooter))
                    }
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
        .sheet(item: $model.editor) { editor in
            PlannedStayEditor(model: editor)
        }
        .task { await model.load() }
    }

    private var gapSection: some View {
        Section {
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

            NavigationLink {
                PlanningRegionPickerView(
                    model: model.regionSelection,
                    title: String(localized: .plannedStaysHomeRegion),
                    selectedRegion: model.report.forecasts.planning.homeRegion,
                ) { region in
                    try await model.report.forecasts.setHomeRegion(region)
                }
            } label: {
                LabeledContent {
                    Text(model.report.forecasts.planning.homeRegion?.localizedName
                        ?? String(localized: .plannedStayEditorChooseRegion))
                } label: {
                    Label(String(localized: .plannedStaysHomeRegion), systemSymbol: .house)
                }
            }
            .accessibilityAddTraits(model.report.forecasts.planning
                .homeRegion != nil ? [.isSelected] : [])

            if case let .failed(message) = model.saveState {
                Label(message, systemSymbol: .exclamationmarkTriangleFill)
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

    private func stayRow(_ stay: PlannedStay) -> some View {
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

#if DEBUG
    extension PlannedStaysView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Empty", configurations: .fullContentPhoneLightDark) {
                PlannedStaysView(report: PreviewSupport.loadedYearReportModel())
            }
            whereSnapshot(name: "Itinerary", configurations: .fullContentScreenDefaults) {
                PlannedStaysView(report: PreviewSupport.itineraryYearReportModel())
            }
            whereSnapshot(name: "PastTravelPattern", configurations: .fullContentPhoneLightDark) {
                PlannedStaysView(report: PreviewSupport.itineraryYearReportModel(homeRegion: nil))
            }
            whereSnapshot(
                name: "PastExpanded",
                configurations: .fullContentPhoneLightDark
                    + SnapshotConfiguration.combinations(
                        devices: [.iPhoneFullContent],
                        snapshotTypes: [.accessibility],
                    ),
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
        ) { world in
            PlannedStaysView(report: world.report)
        }
    }
#endif
