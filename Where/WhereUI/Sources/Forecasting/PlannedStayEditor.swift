import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Sheet for setting or removing the inclusive departure day for the currently
/// focused region.
struct PlannedStayEditor: View {
    private struct LocationCheckID: Equatable {
        let region: Region
        let driftThreshold: DriftThreshold
    }

    private enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    let region: Region
    let model: LocationForecastModel
    let driftThreshold: DriftThreshold

    @Environment(\.dismiss) private var dismiss
    @State private var through: Date
    @State private var saveState: SaveState = .idle

    init(
        region: Region,
        model: LocationForecastModel,
        driftThreshold: DriftThreshold,
    ) {
        self.region = region
        self.model = model
        self.driftThreshold = driftThreshold
        _through = State(initialValue: model.departureDate(for: region))
    }

    var body: some View {
        NavigationStack {
            Form {
                let locationCheck = model.plannedStayLocationCheck(
                    for: region,
                    driftThreshold: driftThreshold,
                )
                Section {
                    WhereDatePicker(
                        String(localized: .locationForecastEditorDate),
                        selection: $through,
                        earliest: model.minimumDepartureDate,
                        displayedComponents: .date,
                    )
                } footer: {
                    if locationCheck == nil || locationCheck?.status == .accepted {
                        Text(String(localized: .locationForecastEditorFooter))
                    }
                }

                if let locationCheck, locationCheck.status != .accepted {
                    Section {
                        PlannedStayLocationStatusRow(check: locationCheck)
                    } footer: {
                        Text(String(localized: .locationForecastEditorFooter))
                    }
                }

                if case let .failed(message) = saveState {
                    Section {
                        Label(message, systemSymbol: .exclamationmarkTriangleFill)
                            .foregroundStyle(.red)
                    }
                }

                if model.activePlannedStay?.region == region {
                    Section {
                        Button(
                            String(localized: .locationForecastRemovePlan),
                            role: .destructive,
                            action: removePlan,
                        )
                    }
                }
            }
            .navigationTitle(String(localized: .locationForecastEditorTitle))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(saveState == .saving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel), action: dismiss.callAsFunction)
                        .disabled(saveState == .saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saveState == .saving {
                        ProgressView()
                    } else {
                        Button(String(localized: .commonSave), action: save)
                    }
                }
            }
            .task(id: LocationCheckID(region: region, driftThreshold: driftThreshold)) {
                await model.checkCurrentLocation(
                    for: region,
                    driftThreshold: driftThreshold,
                )
            }
        }
    }

    private func save() {
        saveState = .saving
        Task {
            do {
                try await model.set(region: region, through: through)
                dismiss()
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }

    private func removePlan() {
        saveState = .saving
        Task {
            do {
                try await model.clear()
                dismiss()
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}

#if DEBUG
    extension PlannedStayEditor: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "NewPlan", configurations: .screenDefaults) {
                let model = PreviewSupport.plannedStayEditorYearReportModel(
                    currentLocation: LocationSample(
                        timestamp: PreviewSupport.referenceNow,
                        coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                        horizontalAccuracy: 5,
                        source: .gpsSignificantChange,
                    ),
                    plannedStay: nil,
                )
                PlannedStayEditor(
                    region: .newYork,
                    model: model.forecasts,
                    driftThreshold: .km1,
                )
                .background {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                }
            }
            whereSnapshot(name: "ExistingPlan", configurations: .phoneLightDark) {
                let stay = PlannedStay(
                    region: .newYork,
                    through: CalendarDay(year: PreviewSupport.year, month: 8, day: 15),
                )
                let model = PreviewSupport.plannedStayEditorYearReportModel(
                    currentLocation: LocationSample(
                        timestamp: PreviewSupport.referenceNow,
                        coordinate: Coordinate(latitude: 40.7128, longitude: -74.0060),
                        horizontalAccuracy: 5,
                        source: .gpsSignificantChange,
                    ),
                    plannedStay: stay,
                )
                PlannedStayEditor(
                    region: .newYork,
                    model: model.forecasts,
                    driftThreshold: .km1,
                )
                .background {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                }
            }
            whereSnapshot(name: "OutsideRegion", configurations: .phoneLightDark) {
                let model = PreviewSupport.plannedStayEditorYearReportModel(
                    currentLocation: LocationSample(
                        timestamp: PreviewSupport.referenceNow,
                        coordinate: Coordinate(latitude: 35.6762, longitude: 139.6503),
                        horizontalAccuracy: 5,
                        source: .gpsSignificantChange,
                    ),
                    plannedStay: nil,
                )
                PlannedStayEditor(
                    region: .newYork,
                    model: model.forecasts,
                    driftThreshold: .km1,
                )
                .background {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                }
            }
            whereSnapshot(name: "UnavailableLocation", configurations: .phoneLightDark) {
                let model = PreviewSupport.plannedStayEditorYearReportModel(
                    currentLocation: nil,
                    plannedStay: nil,
                )
                PlannedStayEditor(
                    region: .newYork,
                    model: model.forecasts,
                    driftThreshold: .km1,
                )
                .background {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                }
            }
        }
    }

    #Preview {
        PlannedStayEditor.snapshotPreviews
    }
#endif
